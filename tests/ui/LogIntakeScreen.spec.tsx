import React from 'react';
import {
  act,
  render,
  screen,
  userEvent,
  waitFor,
} from '@testing-library/react-native';
import { AccessibilityInfo, Alert } from 'react-native';
import * as Haptics from 'expo-haptics';

import LogIntakeScreen from '~/screens/LogIntakeScreen';
import { formatDoseDateTime } from '~/features/caffeine/presentation';
import { useStore } from '~/state/store';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useLargeText from '~/hooks/useLargeText';
import { navigate } from '~/navigation';
import { getAppPalette } from '~/theme/colors';

jest.mock('@react-native-community/datetimepicker', () => {
  const React = require('react');
  const { View } = require('react-native');
  return { __esModule: true, default: (props: object) => React.createElement(View, props) };
});
jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('expo-haptics', () => ({
  impactAsync: jest.fn().mockResolvedValue(undefined),
  notificationAsync: jest.fn().mockResolvedValue(undefined),
  ImpactFeedbackStyle: { Light: 'light' },
  NotificationFeedbackType: { Success: 'success', Warning: 'warning' },
}));
jest.mock('~/hooks/useAdaptiveLayout', () => ({
  __esModule: true,
  default: jest.fn(),
}));
jest.mock('~/hooks/useLargeText', () => ({
  __esModule: true,
  default: jest.fn(),
}));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

const now = Date.parse('2026-07-24T12:00:00.000Z');
const recentDose = { id: 'recent', timestamp: now - 60_000, mg: 60, source: 'Espresso' };
const editRowName = /^60 mg, Espresso, .*, Manual$/;

type AlertButton = { text: string; style?: string; onPress?: () => void };

describe('LogIntakeScreen', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(Date, 'now').mockReturnValue(now);
    jest
      .spyOn(AccessibilityInfo, 'isReduceMotionEnabled')
      .mockResolvedValue(false);
    jest
      .spyOn(AccessibilityInfo, 'addEventListener')
      .mockReturnValue({
        remove: jest.fn(),
      } as unknown as ReturnType<typeof AccessibilityInfo.addEventListener>);
    jest
      .spyOn(AccessibilityInfo, 'announceForAccessibility')
      .mockImplementation(() => {});
    useStore.setState({
      doses: [recentDose],
      onboarding: {
        completed: true,
        source: 'manual',
        permissionStatus: 'idle',
        appWalkthroughCompleted: true,
        appWalkthroughStep: 9,
      },
    });
    jest.mocked(useAdaptiveLayout).mockReturnValue({
      width: 390, height: 844, isPad: false, isWideLayout: false,
      isIpadWindowed: false, contentMaxWidth: 600, topChromeBuffer: 0,
      horizontalPadding: 16, leftColumnWidth: 358, rightColumnWidth: 358,
    });
    jest.mocked(useLargeText).mockReturnValue(false);
  });

  afterEach(() => jest.restoreAllMocks());

  it('leads with Logged Today, Quick Add, and Custom Entry, then Recent and full history', async () => {
    await render(<LogIntakeScreen />);

    expect(screen.getByTestId('log-compact-layout')).toBeOnTheScreen();
    expect(screen.getByText('Logged Today')).toBeOnTheScreen();
    expect(screen.getByText('Quick Add')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Log Espresso, 60 mg' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Log Drip, 95 mg' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Log Matcha, 70 mg' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Log Energy, 160 mg' })).toBeOnTheScreen();
    expect(
      screen
        .getAllByTestId('sf-symbol', { includeHiddenElements: true })
        .map((symbol) => symbol.props.name),
    ).toEqual(
      expect.arrayContaining([
        'cup.and.saucer.fill',
        'cup.and.saucer.fill',
        'leaf.fill',
        'bolt.fill',
      ]),
    );
    expect(screen.getByRole('button', { name: 'Custom Entry' })).toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Add Data' })).toBeNull();
    expect(screen.getByText('Recent')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Show All Caffeine Data' })).toBeOnTheScreen();
    expect(screen.queryByText('Add Details')).toBeNull();
  });

  it('labels today’s recorded total and its source with no limit or remaining framing', async () => {
    useStore.setState((state) => ({ prefs: { ...state.prefs, dailyLimitMg: 400 } }));
    await render(<LogIntakeScreen />);

    expect(screen.getByLabelText(/^Logged Today, 60 mg, Manual, 1 entry · last at /)).toBeOnTheScreen();
    expect(screen.getByText('Manual')).toBeOnTheScreen();
    expect(screen.queryByText(/remaining|limit|allowance|budget/i)).toBeNull();
    expect(screen.queryByText(/400 mg/)).toBeNull();
  });

  it('marks sample data in the total and keeps sample entries read-only', async () => {
    useStore.setState({
      doses: [{ id: 'demo:dose:0', timestamp: now - 120_000, mg: 80, source: 'Tea' }],
    });
    await render(<LogIntakeScreen />);

    expect(screen.getByLabelText(/^Logged Today, 80 mg, Sample Data,/)).toBeOnTheScreen();
    expect(screen.getByLabelText(/^80 mg, Tea, .*, Sample Data, read-only$/)).toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: /^80 mg, Tea/ })).toBeNull();
  });

  it('keeps sample status quiet and hides the repeated stored sample note', async () => {
    const sample = { id: 'demo:dose:0', timestamp: now - 120_000, mg: 80, source: 'Tea', note: 'Sample data' };
    useStore.setState({
      appearanceMode: 'light',
      doses: [sample, { id: 'demo:dose:1', timestamp: now - 180_000, mg: 95, source: 'Drip', note: 'Iced' }],
    });
    const palette = getAppPalette('light');
    await render(<LogIntakeScreen />);

    for (const status of screen.getAllByText('Sample Data · Read-only')) {
      expect(status).toHaveStyle({ color: palette.textTertiary });
      expect(status).not.toHaveStyle({ color: palette.tint });
    }
    expect(screen.queryByText('Sample data')).toBeNull();
    expect(screen.getByText('Iced')).toBeOnTheScreen();
    expect(screen.getByLabelText(/^80 mg, Tea, .*, Sample Data, read-only$/)).toBeOnTheScreen();
    expect(useStore.getState().doses.find((dose) => dose.id === sample.id)?.note).toBe('Sample data');
  });

  it('shows an honest zero with no source on an empty day', async () => {
    useStore.setState({ doses: [] });
    await render(<LogIntakeScreen />);

    expect(screen.getByText('0 mg')).toBeOnTheScreen();
    expect(screen.getByText('Nothing logged yet today.')).toBeOnTheScreen();
    expect(screen.queryByText('Manual')).toBeNull();
    expect(screen.getByText('No caffeine logged yet.')).toBeOnTheScreen();
  });

  it('shows each recent entry with its full local date and time, amount, and source', async () => {
    await render(<LogIntakeScreen />);

    expect(screen.getByText('60 mg · Espresso')).toBeOnTheScreen();
    expect(screen.getByText(formatDoseDateTime(recentDose.timestamp))).toBeOnTheScreen();
    expect(screen.getByText(formatDoseDateTime(recentDose.timestamp))).toHaveTextContent(/2026/);
    expect(screen.getByText('Manual · Edit')).toBeOnTheScreen();
  });

  it('keeps Today primary while placing Recent beside it on a wide layout', async () => {
    jest.mocked(useAdaptiveLayout).mockReturnValue({
      width: 1180, height: 820, isPad: true, isWideLayout: true,
      isIpadWindowed: false, contentMaxWidth: 1220, topChromeBuffer: 0,
      horizontalPadding: 20, leftColumnWidth: 600, rightColumnWidth: 540,
    });
    await render(<LogIntakeScreen />);

    expect(screen.getByTestId('log-wide-layout')).toBeOnTheScreen();
    expect(screen.getByTestId('log-primary-column')).toHaveStyle({
      width: 600,
    });
    expect(screen.getByTestId('log-supporting-column')).toHaveStyle({
      width: 540,
    });
    expect(screen.getByText('Logged Today')).toBeOnTheScreen();
    expect(screen.getByText('Quick Add')).toBeOnTheScreen();
  });

  it('stacks quick add controls full width at large text sizes', async () => {
    jest.mocked(useLargeText).mockReturnValue(true);
    await render(<LogIntakeScreen />);

    expect(screen.getByRole('button', { name: 'Log Espresso, 60 mg' })).toHaveStyle({ width: '100%' });
    expect(screen.getByRole('button', { name: 'Log Energy, 160 mg' })).toHaveStyle({ width: '100%' });
  });

  it('opens the full-screen Caffeine History route', async () => {
    const user = userEvent.setup();
    await render(<LogIntakeScreen />);

    await user.press(screen.getByRole('button', { name: 'Show All Caffeine Data' }));

    expect(navigate).toHaveBeenCalledWith('CaffeineHistory');
  });

  describe('quick add', () => {
    it('logs once, confirms what was logged, and undoes only that entry', async () => {
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);

      await user.press(screen.getByRole('button', { name: 'Log Drip, 95 mg' }));

      const added = useStore.getState().doses.at(-1)!;
      expect(added).toMatchObject({ timestamp: now, mg: 95, source: 'Drip' });
      expect(useStore.getState().doses).toHaveLength(2);
      expect(screen.getByLabelText(/^Logged Drip, 95 mg at /)).toBeOnTheScreen();
      expect(AccessibilityInfo.announceForAccessibility).toHaveBeenCalledWith(
        expect.stringMatching(/^Logged Drip, 95 mg at .* Undo is available\.$/),
      );

      await user.press(screen.getByRole('button', { name: 'Undo last quick add' }));

      expect(useStore.getState().doses).toEqual([recentDose]);
      expect(screen.getByLabelText('Removed 95 mg · Drip.')).toBeOnTheScreen();
      expect(screen.queryByRole('button', { name: 'Undo last quick add' })).toBeNull();
    });

    it('ignores an accidental double tap, then accepts a deliberate second tap', async () => {
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);

      await user.press(screen.getByRole('button', { name: 'Log Espresso, 60 mg' }));
      await user.press(screen.getByRole('button', { name: 'Log Espresso, 60 mg' }));
      expect(useStore.getState().doses).toHaveLength(2);

      jest.mocked(Date.now).mockReturnValue(now + 1_000);
      await user.press(screen.getByRole('button', { name: 'Log Espresso, 60 mg' }));
      expect(useStore.getState().doses).toHaveLength(3);
    });

    it('still saves when best-effort haptics rejects', async () => {
      jest.mocked(Haptics.notificationAsync).mockRejectedValueOnce(new Error('unavailable'));
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);

      await user.press(screen.getByRole('button', { name: 'Log Drip, 95 mg' }));

      expect(Haptics.notificationAsync).toHaveBeenCalledTimes(1);
      expect(useStore.getState().doses.at(-1)).toMatchObject({ timestamp: now, mg: 95, source: 'Drip' });
      expect(screen.getByLabelText(/^Logged Drip, 95 mg at /)).toBeOnTheScreen();
    });
  });

  describe('correcting an entry', () => {
    it('picks the source from a radio group that marks the current choice', async () => {
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);

      await user.press(screen.getByRole('button', { name: editRowName }));
      expect(screen.getByRole('radio', { name: 'Espresso' })).toBeChecked();

      await user.press(screen.getByRole('radio', { name: 'Tea' }));
      expect(screen.getByRole('radio', { name: 'Tea' })).toBeChecked();
      expect(screen.getByRole('radio', { name: 'Espresso' })).not.toBeChecked();
    });

    it('edits amount and note in place, keeping the same record', async () => {
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);

      await user.press(screen.getByRole('button', { name: editRowName }));
      expect(screen.getByRole('header', { name: 'Edit Entry' })).toBeOnTheScreen();
      expect(screen.getByLabelText('Amount')).toHaveProp('value', '60');

      await user.clear(screen.getByLabelText('Amount'));
      await user.type(screen.getByLabelText('Amount'), '75');
      await user.type(screen.getByLabelText('Note'), 'Double shot');
      await user.press(screen.getByRole('button', { name: 'Save' }));

      expect(useStore.getState().doses).toEqual([
        { id: 'recent', timestamp: recentDose.timestamp, mg: 75, source: 'Espresso', note: 'Double shot' },
      ]);
      expect(screen.getByLabelText('Entry updated.')).toBeOnTheScreen();
      expect(screen.getByText('75 mg · Espresso')).toBeOnTheScreen();
    });

    it('does not save an invalid correction', async () => {
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);

      await user.press(screen.getByRole('button', { name: editRowName }));
      await user.clear(screen.getByLabelText('Amount'));
      await user.type(screen.getByLabelText('Amount'), '0');

      expect(screen.getByText('Amount must be between 1 and 1999 mg.')).toBeOnTheScreen();
      expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
      expect(useStore.getState().doses).toEqual([recentDose]);
    });

    it('asks before deleting and removes nothing when cancelled', async () => {
      const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);

      await user.press(screen.getByRole('button', { name: editRowName }));
      await user.press(screen.getByRole('button', { name: 'Delete Entry' }));

      expect(alert).toHaveBeenCalledWith(
        'Delete this entry?',
        expect.stringContaining('60 mg · Espresso'),
        expect.any(Array),
      );
      expect(useStore.getState().doses).toEqual([recentDose]);
      const buttons = alert.mock.calls[0][2] as AlertButton[];
      expect(buttons.find((button) => button.text === 'Cancel')?.style).toBe('cancel');
      expect(buttons.find((button) => button.text === 'Delete')?.style).toBe('destructive');
    });

    it('deletes only after confirmation and closes the sheet', async () => {
      const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
      useStore.setState({
        doses: [recentDose, { id: 'other', timestamp: now - 3_600_000, mg: 95, source: 'Drip' }],
      });
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);

      await user.press(screen.getByRole('button', { name: editRowName }));
      await user.press(screen.getByRole('button', { name: 'Delete Entry' }));
      const buttons = alert.mock.calls[0][2] as AlertButton[];
      await act(() => buttons.find((button) => button.text === 'Delete')?.onPress?.());

      expect(useStore.getState().doses.map((dose) => dose.id)).toEqual(['other']);
      expect(screen.getByLabelText('Entry deleted.')).toBeOnTheScreen();
      expect(screen.queryByRole('header', { name: 'Edit Entry' })).toBeNull();
      expect(screen.queryByRole('button', { name: 'Delete Entry' })).toBeNull();
    });
  });

  describe('custom entry', () => {
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
      expect(
        AccessibilityInfo.announceForAccessibility,
      ).toHaveBeenCalledWith('Caffeine intake saved.');
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

    it('does not carry a correction into a new custom entry', async () => {
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);

      await user.press(screen.getByRole('button', { name: editRowName }));
      await user.press(screen.getByRole('button', { name: 'Cancel' }));
      await user.press(screen.getByRole('button', { name: 'Custom Entry' }));

      expect(screen.getByRole('header', { name: 'Custom Entry' })).toBeOnTheScreen();
      expect(screen.getByLabelText('Amount')).toHaveProp('value', '80');
      expect(screen.queryByRole('button', { name: 'Delete Entry' })).toBeNull();
    });

    it('keeps haptics but drops modal animation when Reduce Motion is enabled', async () => {
      jest
        .mocked(AccessibilityInfo.isReduceMotionEnabled)
        .mockResolvedValue(true);
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);
      await waitFor(() =>
        expect(
          AccessibilityInfo.isReduceMotionEnabled,
        ).toHaveBeenCalledTimes(1),
      );

      await user.press(screen.getByRole('button', { name: 'Log Drip, 95 mg' }));
      // Haptics are feedback, not motion, so Reduce Motion leaves them on.
      expect(Haptics.notificationAsync).toHaveBeenCalledTimes(1);

      await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
      expect(screen.getByTestId('health-form-sheet-modal')).toHaveProp(
        'animationType',
        'none',
      );
      await user.press(screen.getByRole('button', { name: 'Date and Time' }));
      expect(screen.getByTestId('caffeine-time-picker-modal')).toHaveProp(
        'animationType',
        'none',
      );
    });

    it('keeps custom save disabled and explains an invalid future time', async () => {
      const user = userEvent.setup();
      await render(<LogIntakeScreen />);
      await user.press(screen.getByRole('button', { name: 'Custom Entry' }));
      await user.press(screen.getByRole('button', { name: 'Date and Time' }));
      await act(() => screen.getByTestId('caffeine-time-picker').props.onChange({}, new Date(now + 1)));
      await user.press(screen.getByRole('button', { name: 'Done' }));

      expect(screen.getByText('Time cannot be in the future.')).toBeOnTheScreen();
      expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
    });
  });
});
