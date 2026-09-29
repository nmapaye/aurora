import { NO_HEALTH_SLEEP_MESSAGE } from '~/features/sleep/healthImport';
import { formatSleepDate } from '~/features/sleep/signals';
import React from 'react';
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  userEvent,
  waitFor,
} from '@testing-library/react-native';
import { AccessibilityInfo } from 'react-native';

import AppleHealth from '~/services/platform/health/appleHealth';
import SleepScreen from '~/screens/SleepScreen';
import { jsonStringStorage } from '~/services/storage';
import { useStore } from '~/state/store';

jest.mock('@react-native-community/datetimepicker', () => {
  const React = require('react');
  const { View } = require('react-native');
  return { __esModule: true, default: (props: object) => React.createElement(View, props) };
});
jest.mock('~/services/platform/health/appleHealth', () => ({
  __esModule: true,
  default: {
    isAvailable: jest.fn(),
    requestAuthorization: jest.fn(),
    getSleepSamples: jest.fn(),
  },
  makeHealthSleepSessionId: ({ start, end }: { start: number; end: number }) =>
    `healthkit:sleep:${start}:${end}`,
}));
jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

const health = jest.mocked(AppleHealth);
const now = Date.parse('2026-07-24T12:00:00.000Z');
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

describe('SleepScreen', () => {
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
    health.isAvailable.mockResolvedValue(true);
    health.requestAuthorization.mockResolvedValue(true);
    health.getSleepSamples.mockResolvedValue([]);
    useStore.setState({
      doses: [],
      sleeps: [],
      demoMode: false,
      onboarding: {
        completed: true,
        source: 'manual',
        permissionStatus: 'idle',
        appWalkthroughCompleted: true,
        appWalkthroughStep: 9,
      },
      healthSync: { importedCount: 0, importStatus: 'idle' },
    });
  });

  afterEach(() => jest.restoreAllMocks());

  it('presents the Health-style week/month hierarchy and honest empty chart', async () => {
    await render(<SleepScreen />);

    expect(screen.getAllByText('Sleep').length).toBeGreaterThan(0);
    expect(screen.getByRole('button', { name: 'Add Data' })).toBeOnTheScreen();
    expect(screen.getByRole('tab', { name: 'Week' })).toHaveProp('accessibilityState', { selected: true });
    expect(screen.getByTestId('sleep-compact-layout')).toBeOnTheScreen();
    expect(screen.getByLabelText(/No sleep data is available/)).toBeOnTheScreen();
    // No faux metric: an empty range has no big "No Data" or zero value.
    expect(screen.queryByText('No Data')).not.toBeOnTheScreen();
    expect(screen.queryByText('0h 0m')).not.toBeOnTheScreen();
    expect(
      screen.getByRole('button', {
        name: 'Most Recent Sleep, No data, No sleep recorded in the last 7 days.',
      }),
    ).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Sleep Data, Manual mode' })).toBeOnTheScreen();
  });

  it('saves a validated manual session and announces confirmation', async () => {
    const user = userEvent.setup();
    await render(<SleepScreen />);

    await user.press(screen.getByRole('button', { name: 'Add Data' }));
    expect(screen.getByRole('header', { name: 'Add Sleep' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Start time' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'End time' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Start time' }).props.accessibilityValue?.text).toContain('Jul');
    expect(screen.getByRole('button', { name: 'End time' }).props.accessibilityValue?.text).toContain('Jul');
    await user.press(screen.getByRole('button', { name: 'Save' }));

    expect(useStore.getState().sleeps[0]).toMatchObject({
      id: expect.stringMatching(/^manual:sleep:/),
      type: 'sleep',
    });
    expect(screen.getByLabelText('Sleep session saved.')).toBeOnTheScreen();
    expect(AccessibilityInfo.announceForAccessibility).toHaveBeenCalledWith(
      'Sleep session saved.',
    );
  });

  it('suppresses Add Sleep sheet animation when system Reduce Motion is enabled', async () => {
    jest
      .mocked(AccessibilityInfo.isReduceMotionEnabled)
      .mockResolvedValue(true);
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await waitFor(() =>
      expect(AccessibilityInfo.isReduceMotionEnabled).toHaveBeenCalled(),
    );

    await user.press(screen.getByRole('button', { name: 'Add Data' }));

    expect(screen.getByTestId('health-form-sheet-modal')).toHaveProp(
      'animationType',
      'none',
    );
  });

  it('does not retain an Add Sleep picker after cancel or save', async () => {
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: 'Add Data' }));
    await user.press(screen.getByRole('button', { name: 'End time' }));
    expect(screen.getByTestId('sleep-end-picker')).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Cancel' }));
    await user.press(screen.getByRole('button', { name: 'Add Data' }));
    expect(screen.queryByTestId('sleep-end-picker')).not.toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'End time' }));
    await user.press(screen.getByRole('button', { name: 'Save' }));
    await user.press(screen.getByRole('button', { name: 'Add Data' }));
    expect(screen.queryByTestId('sleep-end-picker')).not.toBeOnTheScreen();
  });

  it('shows a validation message and disables save when the end is in the future', async () => {
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: 'Add Data' }));
    await user.press(screen.getByRole('button', { name: 'End time' }));
    await act(() => screen.getByTestId('sleep-end-picker').props.onChange({}, new Date(now + 1)));

    expect(screen.getByText('End time cannot be in the future.')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
  });

  it('refreshes exactly the most recent 30 days from Health', async () => {
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: /^Sleep Data/ }));
    await user.press(screen.getByRole('button', { name: 'Connect to Health' }));

    await waitFor(() =>
      expect(health.getSleepSamples).toHaveBeenCalledWith(now - 30 * 24 * 60 * 60 * 1000, now),
    );
    expect(screen.getAllByText('No sleep found').length).toBeGreaterThan(0);
    expect(screen.getByText(NO_HEALTH_SLEEP_MESSAGE)).toBeOnTheScreen();
    expect(useStore.getState().healthSync.importStatus).toBe('succeeded');
  });

  it('persists first-time granted authorization before a deferred query fails and remounts', async () => {
    const query = deferred<Awaited<ReturnType<typeof AppleHealth.getSleepSamples>>>();
    health.getSleepSamples.mockReturnValueOnce(query.promise);
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: /^Sleep Data/ }));
    await user.press(screen.getByRole('button', { name: 'Connect to Health' }));

    await waitFor(() =>
      expect(useStore.getState()).toMatchObject({
        onboarding: {
          source: 'healthkit',
          permissionStatus: 'granted',
        },
        healthSync: { importStatus: 'importing' },
      }),
    );

    await act(() => query.reject(new Error('Health database unavailable')));

    await waitFor(() => expect(screen.getAllByText('Health refresh failed. Health database unavailable').length).toBeGreaterThan(0));
    expect(screen.queryByText(NO_HEALTH_SLEEP_MESSAGE)).not.toBeOnTheScreen();
    expect(screen.queryByText('Health connected')).not.toBeOnTheScreen();
    expect(useStore.getState()).toMatchObject({
      onboarding: {
        source: 'healthkit',
        permissionStatus: 'granted',
      },
      healthSync: { importStatus: 'failed' },
    });

    const persisted = useStore.persist.getOptions().partialize!(
      useStore.getState(),
    );
    const serializedPersistedState = JSON.stringify({
      state: persisted,
      version: 6,
    });
    await cleanup();
    useStore.setState({
      onboarding: {
        completed: true,
        source: 'manual',
        permissionStatus: 'idle',
        appWalkthroughCompleted: true,
        appWalkthroughStep: 9,
      },
      healthSync: { importedCount: 0, importStatus: 'idle' },
    });
    jsonStringStorage.setItem('aurora/state', serializedPersistedState);

    await useStore.persist.rehydrate();

    expect(useStore.getState()).toMatchObject({
      onboarding: {
        source: 'healthkit',
        permissionStatus: 'granted',
      },
      healthSync: { importStatus: 'failed' },
    });
    await render(<SleepScreen />);
    await userEvent
      .setup()
      .press(screen.getByRole('button', { name: /^Sleep Data/ }));
    expect(
      screen.getAllByText(
        'Health refresh failed. Health database unavailable',
      ).length,
    ).toBeGreaterThan(0);
    expect(screen.queryByText('Health connected')).not.toBeOnTheScreen();
  });

  it('keeps granted authorization when a first-time query payload is malformed', async () => {
    health.getSleepSamples.mockResolvedValueOnce(undefined as never);
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: /^Sleep Data/ }));
    await user.press(screen.getByRole('button', { name: 'Connect to Health' }));

    await waitFor(() => expect(screen.getAllByText(/Health refresh failed/).length).toBeGreaterThan(0));
    expect(screen.queryByText(NO_HEALTH_SLEEP_MESSAGE)).not.toBeOnTheScreen();
    expect(useStore.getState()).toMatchObject({
      onboarding: {
        source: 'healthkit',
        permissionStatus: 'granted',
      },
      healthSync: { importStatus: 'failed' },
    });
  });

  it('recovers a failed first-time import on a valid retry', async () => {
    const sample = {
      start: now - 8 * 60 * 60 * 1000,
      end: now,
    };
    health.getSleepSamples
      .mockRejectedValueOnce(new Error('Health database unavailable'))
      .mockResolvedValueOnce([sample]);
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: /^Sleep Data/ }));
    await user.press(screen.getByRole('button', { name: 'Connect to Health' }));
    await waitFor(() =>
      expect(useStore.getState().healthSync.importStatus).toBe('failed'),
    );

    await user.press(screen.getByRole('button', { name: 'Refresh Sleep' }));

    await waitFor(() =>
      expect(useStore.getState().healthSync.importStatus).toBe('succeeded'),
    );
    expect(useStore.getState().onboarding).toMatchObject({
      source: 'healthkit',
      permissionStatus: 'granted',
    });
    expect(useStore.getState().sleeps).toEqual([
      {
        id: `healthkit:sleep:${sample.start}:${sample.end}`,
        ...sample,
        type: 'sleep',
      },
    ]);
  });

  it('keeps an unavailable first connection on the manual unsupported path', async () => {
    health.isAvailable
      .mockResolvedValueOnce(true)
      .mockResolvedValueOnce(false);
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: /^Sleep Data/ }));
    await user.press(screen.getByRole('button', { name: 'Connect to Health' }));

    await waitFor(() =>
      expect(useStore.getState()).toMatchObject({
        onboarding: {
          source: 'manual',
          permissionStatus: 'unsupported',
        },
        healthSync: { importStatus: 'idle' },
      }),
    );
    expect(health.getSleepSamples).not.toHaveBeenCalled();
  });

  it('keeps denied first-time authorization on the manual denied path', async () => {
    health.requestAuthorization.mockResolvedValueOnce(false);
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: /^Sleep Data/ }));
    await user.press(screen.getByRole('button', { name: 'Connect to Health' }));

    await waitFor(() =>
      expect(useStore.getState()).toMatchObject({
        onboarding: {
          source: 'manual',
          permissionStatus: 'denied',
        },
        healthSync: { importStatus: 'idle' },
      }),
    );
    expect(health.getSleepSamples).not.toHaveBeenCalled();
  });

  it.each([
    ['unsupported', 'healthkit', 'Health unavailable'],
    ['denied', 'healthkit', 'Health not connected'],
    // Choosing manual logging during setup also stores 'unsupported'.
    ['unsupported', 'manual', 'Manual mode'],
  ] as const)('keeps %s (%s) Health state visibly distinct', async (permissionStatus, source, expected) => {
    useStore.getState().setOnboarding({ permissionStatus, source });
    await render(<SleepScreen />);

    expect(screen.getByText(expected)).toBeOnTheScreen();
  });

  it('shows sample-data state distinctly from manual and Health states', async () => {
    useStore.setState({ demoMode: true });
    await render(<SleepScreen />);
    await userEvent.setup().press(screen.getByRole('button', { name: /^Sleep Data/ }));

    expect(screen.getAllByText('Sample Data').length).toBeGreaterThan(0);
    expect(screen.getByText('Example sleep and caffeine data is active.')).toBeOnTheScreen();
  });

  it('shows only quiet progress, never a timing number, at 1 of 14 paired nights', async () => {
    // Last dose 3 h before an 8 h sleep ending now: 180 min, a single night.
    useStore.setState({
      sleeps: [{ id: 'manual:sleep:timing', start: now - 8 * HOUR, end: now, type: 'sleep' }],
      doses: [{ id: 'dose:timing', timestamp: now - 11 * HOUR, mg: 80 }],
    });
    await render(<SleepScreen />);

    const timing = screen.getByTestId('caffeine-timing-gathering');
    expect(timing).toHaveProp(
      'accessibilityLabel',
      expect.stringContaining('Caffeine timing before sleep. 1 of 14 nights so far'),
    );
    expect(screen.queryByTestId('caffeine-timing-observed')).not.toBeOnTheScreen();
    expect(screen.queryByText(/180 min|3h\b|180–180|3h – 3h/)).not.toBeOnTheScreen();
    expect(screen.queryByText('Caffeine Impact')).not.toBeOnTheScreen();
    expect(screen.queryByText(/pattern|correlat|affect|impact/i)).not.toBeOnTheScreen();
  });

  it('shows one observed median with its night count at 14 paired nights and keeps the distribution behind a disclosure', async () => {
    const sleeps = Array.from({ length: 14 }, (_, index) => ({
      id: `manual:sleep:${index}`,
      start: now - (index + 1) * DAY - 8 * HOUR,
      end: now - (index + 1) * DAY,
      type: 'sleep' as const,
    }));
    useStore.setState({
      sleeps,
      doses: sleeps.map((sleep, index) => ({
        id: `dose:${index}`,
        timestamp: sleep.start - 3 * HOUR,
        mg: 80,
      })),
    });
    const user = userEvent.setup();
    await render(<SleepScreen />);

    expect(
      screen.getByLabelText(
        'Caffeine timing before sleep, 3h, Last 30 days, Median time from last logged caffeine to sleep · 14 nights',
      ),
    ).toBeOnTheScreen();
    expect(screen.queryByText('Middle 80% of nights')).not.toBeOnTheScreen();

    const disclosure = screen.getByRole('button', { name: 'Timing distribution' });
    expect(disclosure).toHaveProp('accessibilityState', { expanded: false });
    await user.press(disclosure);

    expect(screen.getByText('Middle 80% of nights')).toBeOnTheScreen();
    expect(screen.getByText('3h – 3h')).toBeOnTheScreen();
    expect(screen.queryByText(/correlat|caus|affect|impact/i)).not.toBeOnTheScreen();
  });

  it('has no dose plan, allowance, or dose-writing action', async () => {
    useStore.setState({
      sleeps: [{ id: 'manual:sleep:plan', start: now - 8 * HOUR, end: now - HOUR, type: 'sleep' }],
    });
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: /^Sleep Data/ }));

    expect(screen.queryByText('Next Best Actions')).not.toBeOnTheScreen();
    expect(screen.queryByText(/200 mg|Log First Dose|Recommended at|Kickstart|Sustain|Top-up/)).not.toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: /Dose/ })).not.toBeOnTheScreen();
    expect(useStore.getState().doses).toEqual([]);
  });

  it.each([
    ['manual:sleep:recent', 'Manual'],
    ['healthkit:sleep:recent', 'Health'],
    ['demo:sleep:recent', 'Sample Data'],
  ])('labels the most recent sleep from %s as %s with its date and target context', async (id, source) => {
    useStore.setState({
      sleeps: [{ id, start: now - 8.5 * HOUR, end: now - HOUR, type: 'sleep' }],
      prefs: { ...useStore.getState().prefs, targetSleep: 8 },
    });
    await render(<SleepScreen />);

    const card = screen.getByRole('button', { name: /^Most Recent Sleep, 7h 30m/ });
    expect(card.props.accessibilityLabel).toContain(`Today · ${source}`);
    expect(card.props.accessibilityLabel).toContain('30m under your 8h target');
  });

  it('shows the actual date of an older sample night in the primary context', async () => {
    useStore.setState({
      sleeps: [{ id: 'demo:sleep:old', start: now - 6 * DAY - 8 * HOUR, end: now - 6 * DAY, type: 'sleep' }],
    });
    await render(<SleepScreen />);

    const date = formatSleepDate(now - 6 * DAY);
    const card = screen.getByRole('button', { name: /^Most Recent Sleep, 8h 0m/ });
    expect(card.props.accessibilityLabel).toContain('6 days ago · Sample Data');
    expect(screen.getByText(new RegExp(`^${date} · `))).toBeOnTheScreen();
    expect(screen.getByText('6 days ago')).toBeOnTheScreen();
    expect(screen.queryByText('Latest Night')).not.toBeOnTheScreen();
  });

  it('opens Sleep History from the Sleep Data entry and from the most recent sleep', async () => {
    const { navigate } = jest.requireMock('~/navigation') as { navigate: jest.Mock };
    useStore.setState({
      sleeps: [{ id: 'healthkit:sleep:1', start: now - 8 * HOUR, end: now - HOUR, type: 'sleep' }],
    });
    const user = userEvent.setup();
    await render(<SleepScreen />);

    await user.press(screen.getByRole('button', { name: /^Most Recent Sleep/ }));
    expect(navigate).toHaveBeenLastCalledWith('SleepHistory');

    navigate.mockClear();
    const entry = screen.getByRole('button', { name: /^Sleep Data/ });
    expect(entry).toHaveProp('accessibilityState', { expanded: false });
    await user.press(entry);
    expect(screen.getByTestId('sleep-data-panel')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Connect to Health' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Load Sample Data' })).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Show All Data, 1 session' }));
    expect(navigate).toHaveBeenLastCalledWith('SleepHistory');
  });

  describe('chart inspection', () => {
    // Today and two days ago have sleep; yesterday is missing.
    function seedWeek() {
      useStore.setState({
        sleeps: [
          { id: 'manual:sleep:today', start: now - 8 * HOUR, end: now - HOUR, type: 'sleep' },
          { id: 'manual:sleep:two-days', start: now - 2 * DAY - 7 * HOUR, end: now - 2 * DAY, type: 'sleep' },
        ],
      });
    }

    async function renderLaidOutChart() {
      seedWeek();
      await render(<SleepScreen />);
      const plot = screen.getByTestId('sleep-bars-plot');
      await fireEvent(plot, 'layout', {
        nativeEvent: { layout: { x: 0, y: 0, width: 700, height: 104 } },
      });
      return screen.getByTestId('sleep-bars-plot');
    }

    function tap(plot: ReturnType<typeof screen.getByTestId>, x: number) {
      const touch = {
        touchActive: true,
        startPageX: x,
        startPageY: 50,
        startTimeStamp: 1,
        currentPageX: x,
        currentPageY: 50,
        currentTimeStamp: 2,
        previousPageX: x,
        previousPageY: 50,
        previousTimeStamp: 1,
      };
      const event = {
        nativeEvent: { locationX: x, locationY: 50, pageX: x, pageY: 50 },
        touchHistory: {
          numberActiveTouches: 1,
          indexOfSingleActiveTouch: 0,
          mostRecentTimeStamp: 2,
          touchBank: [touch],
        },
      };
      return act(async () => {
        plot.props.onStartShouldSetResponder(event);
        plot.props.onResponderGrant(event);
        plot.props.onResponderRelease(event);
      });
    }

    it('is one adjustable element whose value defaults to the latest recorded day', async () => {
      const plot = await renderLaidOutChart();

      expect(plot).toHaveProp('accessibilityRole', 'adjustable');
      expect(plot.props.accessibilityLabel).toMatch(/^Time Asleep, 7 days ending/);
      expect(plot.props.accessibilityValue.text).toMatch(/, 7h 0m$/);
    });

    it('reads a missing day as missing, not zero, when stepped with VoiceOver', async () => {
      await renderLaidOutChart();

      await fireEvent(screen.getByTestId('sleep-bars-plot'), 'accessibilityAction', {
        nativeEvent: { actionName: 'decrement' },
      });
      expect(screen.getByTestId('sleep-bars-plot').props.accessibilityValue.text).toMatch(
        /, No sleep recorded$/,
      );
      expect(screen.getByText('No sleep recorded', { includeHiddenElements: true })).toBeTruthy();

      await fireEvent(screen.getByTestId('sleep-bars-plot'), 'accessibilityAction', {
        nativeEvent: { actionName: 'decrement' },
      });
      expect(screen.getByTestId('sleep-bars-plot').props.accessibilityValue.text).toMatch(/, 7h 0m$/);
    });

    it('selects the tapped day and shows its date and duration in the readout', async () => {
      const plot = await renderLaidOutChart();

      // Seven bars across 700 pt: x = 450 is the fifth, two days ago.
      await tap(plot, 450);
      const text = screen.getByTestId('sleep-bars-plot').props.accessibilityValue.text;
      expect(text).toMatch(/, 7h 0m$/);
      expect(text).toContain(
        new Intl.DateTimeFormat(undefined, { weekday: 'short', month: 'short', day: 'numeric' }).format(
          new Date(new Date(now - 2 * DAY).setHours(0, 0, 0, 0)),
        ),
      );

      // x = 550 is the sixth bar, yesterday, which has no record.
      await tap(screen.getByTestId('sleep-bars-plot'), 550);
      expect(screen.getByTestId('sleep-bars-plot').props.accessibilityValue.text).toMatch(
        /, No sleep recorded$/,
      );
    });
  });
});
