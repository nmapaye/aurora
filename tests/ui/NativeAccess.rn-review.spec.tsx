import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { AppState, Linking } from 'react-native';
import useNativeAccess from '~/hooks/useNativeAccess';
import NativeConfirmScreen from '~/screens/NativeConfirmScreen';
import { useStore } from '~/state/store';
import {
  enqueueNativeURL,
  clearNativeActions,
  pendingNativeAction,
} from '~/features/native/actions';
import { navigate } from '~/navigation';
import {
  publishNativeSnapshot,
  syncNativeNap,
  pendingNativeRequests,
} from '~/services/platform/native';
jest.mock('~/navigation', () => ({ navigate: jest.fn(), goBack: jest.fn() }));
jest.mock('~/services/platform/native', () => ({
  pendingNativeRequests: jest.fn(() => []),
  acknowledgeNativeRequest: jest.fn(),
  clearNativeRequests: jest.fn(),
  publishNativeSnapshot: jest.fn(),
  syncNativeNap: jest.fn(() => Promise.resolve(true)),
}));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
function Harness({ ready = true, navigationReady = true }) {
  useNativeAccess(ready, navigationReady);
  return null;
}
const original = useStore.getState();
beforeEach(() => {
  clearNativeActions();
  jest.clearAllMocks();
  jest.spyOn(Linking, 'getInitialURL').mockResolvedValue(null);
  AppState.currentState = 'active';
  useStore.setState({
    ...original,
    doses: [],
    onboarding: {
      ...original.onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  });
});
afterEach(() => {
  jest.restoreAllMocks();
  useStore.setState(original);
  clearNativeActions();
});
it('holds incoming actions through hydration, navigation readiness, onboarding and walkthrough', async () => {
  useStore.setState({
    onboarding: {
      ...original.onboarding,
      completed: false,
      appWalkthroughCompleted: false,
    },
  });
  enqueueNativeURL('aurora://native/log?amount=95');
  const view = await render(<Harness ready={false} navigationReady={false} />);
  expect(navigate).not.toHaveBeenCalled();
  await view.rerender(<Harness ready navigationReady={false} />);
  await act(() =>
    useStore.setState({
      onboarding: {
        ...original.onboarding,
        completed: true,
        appWalkthroughCompleted: false,
      },
    }),
  );
  await view.rerender(<Harness ready navigationReady />);
  expect(navigate).not.toHaveBeenCalled();
  await act(() =>
    useStore.setState({
      onboarding: {
        ...original.onboarding,
        completed: true,
        appWalkthroughCompleted: true,
      },
    }),
  );
  expect(navigate).toHaveBeenCalledWith('NativeConfirm');
  expect(useStore.getState().doses).toEqual([]);
});
it('preserves the unfinished Log draft while explicitly confirming queued drinks', async () => {
  const draft = {
    mg: '12',
    source: 'Unfinished tea',
    note: 'Keep me',
    timestamp: Date.now() - 60000,
  };
  useStore.setState({ caffeine: { ...original.caffeine, draft } });
  enqueueNativeURL('aurora://native/log?amount=95');
  enqueueNativeURL('aurora://native/log?amount=60');
  await render(<NativeConfirmScreen />);
  expect(useStore.getState().doses).toHaveLength(0);
  await fireEvent.changeText(
    screen.getByLabelText('Shortcut caffeine amount in milligrams'),
    '80',
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Confirm and log drink' }),
  );
  expect(useStore.getState().doses.map((d) => d.mg)).toEqual([80]);
  expect(useStore.getState().caffeine.draft).toEqual(draft);
  expect(
    screen.getByLabelText('Shortcut caffeine amount in milligrams'),
  ).toHaveProp('value', '60');
  await fireEvent.press(
    screen.getByRole('button', { name: 'Cancel Shortcut drink' }),
  );
  expect(useStore.getState().doses).toHaveLength(1);
  expect(pendingNativeAction()).toBeNull();
});
it('ends nap mirroring on finish and clears snapshots and queued actions on all-data reset', async () => {
  const start = Date.now() - 60000;
  useStore.setState({
    sleepRoutines: { ...original.sleepRoutines, timer: { start } },
  });
  await render(<Harness />);
  expect(syncNativeNap).toHaveBeenLastCalledWith(start);
  await act(() =>
    useStore.getState().setSleepRoutines({ timer: { start, end: Date.now() } }),
  );
  expect(syncNativeNap).toHaveBeenLastCalledWith(null);
  await act(() => enqueueNativeURL('aurora://native/log?amount=95'));
  await act(() => useStore.getState().deleteLocalCategories(['all']));
  expect(publishNativeSnapshot).toHaveBeenLastCalledWith(null);
  expect(syncNativeNap).toHaveBeenLastCalledWith(null);
  expect(pendingNativeAction()).toBeNull();
  expect(useStore.getState().sleeps).toEqual([]);
});

it('queues an App Intent inbox action before hydration and opens it only after boot', async () => {
  jest
    .mocked(pendingNativeRequests)
    .mockReturnValueOnce([{ id: 'nap-request', url: 'aurora://native/nap' }]);
  const view = await render(<Harness ready={false} navigationReady={false} />);
  expect(pendingNativeAction()).toEqual({ kind: 'nap' });
  expect(navigate).not.toHaveBeenCalled();
  await view.rerender(<Harness ready navigationReady />);
  expect(navigate).toHaveBeenCalledWith('SleepRoutines');
  expect(pendingNativeAction()).toBeNull();
  expect(useStore.getState().sleeps).toEqual([]);
});

it('rejects an invalid edited Shortcut amount and disables confirmation during walkthrough', async () => {
  enqueueNativeURL('aurora://native/log?amount=95');
  await render(<NativeConfirmScreen />);
  await fireEvent.changeText(
    screen.getByLabelText('Shortcut caffeine amount in milligrams'),
    '-5',
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Confirm and log drink' }),
  );
  expect(useStore.getState().doses).toEqual([]);
  expect(pendingNativeAction()).toEqual({ kind: 'log', amount: 95 });
  await act(() =>
    useStore.setState({
      onboarding: {
        ...useStore.getState().onboarding,
        appWalkthroughCompleted: false,
      },
    }),
  );
  expect(
    screen.getByRole('button', { name: 'Confirm and log drink' }),
  ).toBeDisabled();
  expect(
    screen.getByRole('button', { name: 'Cancel Shortcut drink' }),
  ).toBeDisabled();
});

it('keeps Undo available while reviewing the next queued Shortcut drink', async () => {
  enqueueNativeURL('aurora://native/log?amount=95');
  enqueueNativeURL('aurora://native/log?amount=60');
  await render(<NativeConfirmScreen />);
  expect(screen.getByText('After saving')).toBeOnTheScreen();
  await fireEvent.press(
    screen.getByRole('button', { name: 'Confirm and log drink' }),
  );
  expect(useStore.getState().doses).toHaveLength(1);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Undo caffeine change' }),
  );
  expect(useStore.getState().doses).toEqual([]);
  expect(pendingNativeAction()).toEqual({ kind: 'log', amount: 60 });
});
