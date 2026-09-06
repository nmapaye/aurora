import React from 'react';
import {
  render,
  screen,
  userEvent,
  fireEvent,
  within,
} from '@testing-library/react-native';
import { AccessibilityInfo } from 'react-native';
import LogIntakeScreen from '~/screens/LogIntakeScreen';
import DashboardScreen from '~/screens/DashboardScreen';
import CaffeineHistoryScreen from '~/screens/CaffeineHistoryScreen';
import { useStore } from '~/state/store';
import { defaultCaffeineState } from '~/features/caffeine/upgrades';

jest.mock('~/navigation', () => ({ navigate: jest.fn(), goBack: jest.fn() }));
jest.mock('~/hooks/useAdaptiveLayout', () => ({
  __esModule: true,
  default: () => ({
    width: 390,
    height: 844,
    isPad: false,
    isWideLayout: false,
    isIpadWindowed: false,
    contentMaxWidth: 600,
    topChromeBuffer: 0,
    horizontalPadding: 16,
    leftColumnWidth: 358,
    rightColumnWidth: 358,
  }),
}));
jest.mock('@react-native-community/datetimepicker', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    __esModule: true,
    default: (props: object) => React.createElement(View, props),
  };
});
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 34, left: 0 }),
}));
const now = new Date(2026, 8, 7, 12).getTime();
beforeEach(() => {
  jest.spyOn(Date, 'now').mockReturnValue(now);
  jest
    .spyOn(AccessibilityInfo, 'isReduceMotionEnabled')
    .mockResolvedValue(true);
  jest
    .spyOn(AccessibilityInfo, 'announceForAccessibility')
    .mockImplementation(() => {});
  useStore.setState({
    doses: [],
    caffeine: {
      ...defaultCaffeineState,
      drinks: [],
      draft: null,
      zeroDays: [],
    },
    doseUndo: null,
    onboarding: {
      completed: true,
      source: 'manual',
      permissionStatus: 'unsupported',
      appWalkthroughCompleted: true,
      appWalkthroughStep: 9,
    },
  });
});
afterEach(() => jest.restoreAllMocks());
it('shows the same reordered favorites on Summary and Log', async () => {
  useStore.getState().setFavoriteDrinks(['energy', 'espresso', 'matcha']);
  const first = await render(<DashboardScreen />);
  const labels = () =>
    screen
      .getAllByRole('button')
      .map((button) => button.props.accessibilityLabel)
      .filter(
        (label) =>
          typeof label === 'string' && /^(Energy|Espresso|Matcha) /.test(label),
      )
      .map((label) => label.replaceAll(' ', ''));
  expect(labels()).toEqual(['Energy160mg', 'Espresso60mg', 'Matcha70mg']);
  await first.unmount();
  await render(<LogIntakeScreen />);
  expect(labels()).toEqual(['Energy160mg', 'Espresso60mg', 'Matcha70mg']);
});
it('marks a zero day through Log and clears it only after confirming a dose', async () => {
  const user = userEvent.setup();
  await render(<LogIntakeScreen />);
  await user.press(
    screen.getByRole('button', { name: 'Mark today caffeine-free' }),
  );
  expect(useStore.getState().caffeine.zeroDays).toHaveLength(1);
  await user.press(screen.getByRole('button', { name: 'Espresso 60 mg' }));
  expect(useStore.getState().caffeine.zeroDays).toHaveLength(1);
  await user.press(screen.getByRole('button', { name: 'Log drink' }));
  expect(useStore.getState().caffeine.zeroDays).toEqual([]);
  expect(
    within(screen.getByTestId('app-screen-overlay')).getByRole('button', {
      name: 'Undo caffeine change',
    }),
  ).toBeOnTheScreen();
});
it('repeats an entry, edits the amount in Log, and saves a new dose at the current time', async () => {
  const original = {
    id: 'original',
    mg: 80,
    timestamp: now - 3600000,
    source: 'Tea',
    note: 'Morning',
  };
  useStore.setState({ doses: [original] });
  const user = userEvent.setup();
  const history = await render(<CaffeineHistoryScreen />);
  await user.press(screen.getByRole('button', { name: 'Repeat' }));
  await history.unmount();
  await render(<LogIntakeScreen />);
  await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
  await user.clear(screen.getByLabelText('Amount'));
  await user.type(screen.getByLabelText('Amount'), '120');
  await user.press(screen.getByRole('button', { name: 'Save' }));
  expect(useStore.getState().doses[0]).toEqual(original);
  expect(useStore.getState().doses[1]).toMatchObject({
    mg: 120,
    timestamp: now,
    source: 'Tea',
    note: 'Morning',
  });
  expect(useStore.getState().caffeine.draft).toBeNull();
});
it('preserves note and time edits across History to Log to History cancellation and save', async () => {
  useStore.setState({
    doses: [
      {
        id: 'original',
        mg: 80,
        timestamp: now - 3600000,
        source: 'Tea',
        note: 'Morning',
      },
    ],
  });
  const user = userEvent.setup();
  const history = await render(<CaffeineHistoryScreen />);
  await user.press(screen.getByRole('button', { name: 'Edit' }));
  await user.press(screen.getByRole('button', { name: 'Cancel' }));
  await history.unmount();
  const log = await render(<LogIntakeScreen />);
  await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
  await user.clear(screen.getByLabelText('Note'));
  await user.type(screen.getByLabelText('Note'), 'Changed in Log');
  await user.press(screen.getByRole('button', { name: 'Time' }));
  await fireEvent(
    screen.getByTestId('caffeine-time-picker'),
    'onChange',
    { type: 'set' },
    new Date(now - 7200000),
  );
  await user.press(screen.getByRole('button', { name: 'Done' }));
  await user.press(screen.getByRole('button', { name: 'Cancel' }));
  await log.unmount();
  await render(<CaffeineHistoryScreen />);
  await user.press(screen.getByRole('button', { name: 'Cancel' }));
  await user.press(screen.getByRole('button', { name: 'Edit' }));
  await user.press(screen.getByRole('button', { name: 'Save' }));
  expect(useStore.getState().doses[0]).toMatchObject({
    id: 'original',
    note: 'Changed in Log',
    timestamp: now - 7200000,
  });
  expect(useStore.getState().caffeine.draft).toBeNull();
});
