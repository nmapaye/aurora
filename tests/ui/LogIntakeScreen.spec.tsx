import React from 'react';
import {
  act,
  render,
  screen,
  userEvent,
  waitFor,
} from '@testing-library/react-native';
import { AccessibilityInfo } from 'react-native';
import * as Haptics from 'expo-haptics';

import LogIntakeScreen from '~/screens/LogIntakeScreen';
import { useStore } from '~/state/store';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import { navigate } from '~/navigation';

jest.mock('@react-native-community/datetimepicker', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    __esModule: true,
    default: (props: object) => React.createElement(View, props),
  };
});
jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('expo-haptics', () => ({
  impactAsync: jest.fn().mockResolvedValue(undefined),
  notificationAsync: jest.fn().mockResolvedValue(undefined),
  ImpactFeedbackStyle: { Light: 'light' },
  NotificationFeedbackType: { Success: 'success' },
}));
jest.mock('~/hooks/useAdaptiveLayout', () => ({
  __esModule: true,
  default: jest.fn(),
}));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

const now = Date.parse('2026-07-24T12:00:00.000Z');

describe('LogIntakeScreen', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(Date, 'now').mockReturnValue(now);
    jest
      .spyOn(AccessibilityInfo, 'isReduceMotionEnabled')
      .mockResolvedValue(false);
    jest.spyOn(AccessibilityInfo, 'addEventListener').mockReturnValue({
      remove: jest.fn(),
    } as unknown as ReturnType<typeof AccessibilityInfo.addEventListener>);
    jest
      .spyOn(AccessibilityInfo, 'announceForAccessibility')
      .mockImplementation(() => {});
    useStore.setState({
      caffeine: {
        drinks: [],
        favoriteIds: ['espresso', 'drip', 'matcha', 'energy'],
        draft: null,
        zeroDays: [],
      },
      doseUndo: null,
      doses: [
        { id: 'recent', timestamp: now - 60_000, mg: 60, source: 'Espresso' },
      ],
      onboarding: {
        completed: true,
        source: 'manual',
        permissionStatus: 'idle',
        appWalkthroughCompleted: true,
        appWalkthroughStep: 9,
      },
    });
    jest.mocked(useAdaptiveLayout).mockReturnValue({
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
    });
  });

  afterEach(() => jest.restoreAllMocks());

  it('presents Today, shared Quick Add, Recent, and Add Details on a compact layout', async () => {
    await render(<LogIntakeScreen />);

    expect(screen.getByTestId('log-compact-layout')).toBeOnTheScreen();
    expect(screen.getByText('Caffeine Today')).toBeOnTheScreen();
    expect(screen.getByText('Quick Add')).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Espresso 60 mg' }),
    ).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Drip 95 mg' }),
    ).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Matcha 70 mg' }),
    ).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Energy 160 mg' }),
    ).toBeOnTheScreen();
    expect(
      screen.getAllByTestId('sf-symbol').map((symbol) => symbol.props.name),
    ).toEqual(
      expect.arrayContaining([
        'cup.and.saucer.fill',
        'cup.and.saucer.fill',
        'leaf.fill',
        'bolt.fill',
      ]),
    );
    expect(screen.getByText('Recent')).toBeOnTheScreen();
    expect(screen.getByText('Add Details')).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Custom Entry' }),
    ).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Show All Caffeine Data' }),
    ).toBeOnTheScreen();
  });

  it('keeps Today primary while placing Quick Add and details beside it on a wide layout', async () => {
    jest.mocked(useAdaptiveLayout).mockReturnValue({
      width: 1180,
      height: 820,
      isPad: true,
      isWideLayout: true,
      isIpadWindowed: false,
      contentMaxWidth: 1220,
      topChromeBuffer: 0,
      horizontalPadding: 20,
      leftColumnWidth: 600,
      rightColumnWidth: 540,
    });
    await render(<LogIntakeScreen />);

    expect(screen.getByTestId('log-wide-layout')).toBeOnTheScreen();
    expect(screen.getByTestId('log-primary-column')).toHaveStyle({
      width: 600,
    });
    expect(screen.getByTestId('log-supporting-column')).toHaveStyle({
      width: 540,
    });
    expect(screen.getByText('Caffeine Today')).toBeOnTheScreen();
    expect(screen.getByText('Quick Add')).toBeOnTheScreen();
  });

  it('opens the full-screen Caffeine History route from Add Details', async () => {
    const user = userEvent.setup();
    await render(<LogIntakeScreen />);

    await user.press(
      screen.getByRole('button', { name: 'Show All Caffeine Data' }),
    );

    expect(navigate).toHaveBeenCalledWith('CaffeineHistory');
  });

  it('saves custom timestamp and note, announces success, then resets after save', async () => {
    const user = userEvent.setup();
    await render(<LogIntakeScreen />);

    await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
    await user.clear(screen.getByLabelText('Amount'));
    await user.type(screen.getByLabelText('Amount'), '80');
    await user.clear(screen.getByLabelText('Note'));
    await user.type(screen.getByLabelText('Note'), 'After lunch');
    await user.press(screen.getByRole('button', { name: 'Save' }));

    expect(useStore.getState().doses.at(-1)).toMatchObject({
      timestamp: now,
      mg: 80,
      source: 'Drip',
      note: 'After lunch',
    });
    expect(screen.getByLabelText('Caffeine intake saved.')).toBeOnTheScreen();
    expect(AccessibilityInfo.announceForAccessibility).toHaveBeenCalledWith(
      'Caffeine intake saved.',
    );
    await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
    expect(screen.getByLabelText('Amount')).toHaveProp('value', '80');
    expect(screen.getByLabelText('Note')).toHaveProp('value', '');
  });

  it('retains a custom draft after the sheet is cancelled', async () => {
    const user = userEvent.setup();
    await render(<LogIntakeScreen />);

    await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
    await user.clear(screen.getByLabelText('Amount'));
    await user.type(screen.getByLabelText('Amount'), '125');
    await user.press(screen.getByRole('button', { name: 'Cancel' }));
    await user.press(screen.getByRole('button', { name: 'Custom Entry' }));

    expect(screen.getByLabelText('Amount')).toHaveProp('value', '125');
  });

  it('still saves when best-effort haptics rejects', async () => {
    jest
      .mocked(Haptics.impactAsync)
      .mockRejectedValueOnce(new Error('unavailable'));
    const user = userEvent.setup();
    await render(<LogIntakeScreen />);

    await user.press(screen.getByRole('button', { name: 'Drip 95 mg' }));
    expect(useStore.getState().doses).toHaveLength(1);
    await user.press(screen.getByRole('button', { name: 'Log drink' }));

    expect(Haptics.impactAsync).toHaveBeenCalledTimes(1);
    expect(useStore.getState().doses.at(-1)).toMatchObject({
      timestamp: now,
      mg: 95,
      source: 'Drip',
    });
    expect(screen.getByLabelText('Caffeine intake saved.')).toBeOnTheScreen();
  });

  it('suppresses haptics and modal animation when Reduce Motion is enabled', async () => {
    jest
      .mocked(AccessibilityInfo.isReduceMotionEnabled)
      .mockResolvedValue(true);
    const user = userEvent.setup();
    await render(<LogIntakeScreen />);
    await waitFor(() =>
      expect(AccessibilityInfo.isReduceMotionEnabled).toHaveBeenCalled(),
    );

    await user.press(screen.getByRole('button', { name: 'Drip 95 mg' }));
    expect(useStore.getState().doses).toHaveLength(1);
    await user.press(screen.getByRole('button', { name: 'Log drink' }));
    expect(Haptics.impactAsync).not.toHaveBeenCalled();
    expect(Haptics.notificationAsync).not.toHaveBeenCalled();

    await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
    expect(screen.getByTestId('health-form-sheet-modal')).toHaveProp(
      'animationType',
      'none',
    );
    await user.press(screen.getByRole('button', { name: 'Time' }));
    expect(screen.getByTestId('caffeine-time-picker-modal')).toHaveProp(
      'animationType',
      'none',
    );
  });

  it('keeps custom save disabled and explains an invalid future time', async () => {
    const user = userEvent.setup();
    await render(<LogIntakeScreen />);
    await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
    await user.press(screen.getByRole('button', { name: 'Time' }));
    await act(() =>
      screen
        .getByTestId('caffeine-time-picker')
        .props.onChange({}, new Date(now + 1)),
    );
    await user.press(screen.getByRole('button', { name: 'Done' }));

    expect(screen.getByText('Time cannot be in the future.')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
  });
});

it('recovers an unfinished entry after remount and keeps its original timestamp', async () => {
  jest.spyOn(Date, 'now').mockReturnValue(now);
  useStore.setState({
    doses: [],
    caffeine: {
      drinks: [],
      favoriteIds: ['espresso'],
      draft: null,
      zeroDays: [],
    },
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  });
  jest
    .mocked(useAdaptiveLayout)
    .mockReturnValue({
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
    });
  const user = userEvent.setup();
  const first = await render(<LogIntakeScreen />);
  await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
  expect(useStore.getState().caffeine.draft?.timestamp).toBe(now);
  await user.clear(screen.getByLabelText('Amount'));
  await user.type(screen.getByLabelText('Amount'), '125');
  await first.unmount();
  jest.mocked(Date.now).mockReturnValue(now + 60000);
  await render(<LogIntakeScreen />);
  await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
  expect(screen.getByLabelText('Amount')).toHaveProp('value', '125');
  expect(useStore.getState().caffeine.draft?.timestamp).toBe(now);
  await user.press(
    screen.getByRole('button', { name: 'Discard unfinished entry' }),
  );
  expect(useStore.getState().caffeine.draft).toBeNull();
  jest.restoreAllMocks();
});
