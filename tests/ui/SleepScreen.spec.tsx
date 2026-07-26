import React from 'react';
import {
  act,
  cleanup,
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
jest.mock('~/hooks/useCaffeineCutoff', () => ({
  __esModule: true,
  default: () => ({ nextCutoff: Date.parse('2026-07-24T16:00:00.000Z') }),
}));
jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

const health = jest.mocked(AppleHealth);
const now = Date.parse('2026-07-24T12:00:00.000Z');

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
    expect(screen.getByRole('button', { name: 'W' })).toHaveProp('accessibilityState', { selected: true });
    expect(screen.getByTestId('sleep-compact-layout')).toBeOnTheScreen();
    expect(screen.getByLabelText(/No sleep data is available/)).toBeOnTheScreen();
    expect(screen.getByText('Highlights')).toBeOnTheScreen();
    expect(screen.getByText('Next Best Actions')).toBeOnTheScreen();
    expect(screen.getByText('Options')).toBeOnTheScreen();
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
    await user.press(screen.getByRole('button', { name: 'Data Sources & Access' }));
    await user.press(screen.getByRole('button', { name: 'Connect to Health' }));

    await waitFor(() =>
      expect(health.getSleepSamples).toHaveBeenCalledWith(now - 30 * 24 * 60 * 60 * 1000, now),
    );
    expect(screen.getAllByText('Health connected').length).toBeGreaterThan(0);
    expect(screen.getByText('Health connected with 0 imported sleep samples.')).toBeOnTheScreen();
    expect(useStore.getState().healthSync.importStatus).toBe('succeeded');
  });

  it('persists first-time granted authorization before a deferred query fails and remounts', async () => {
    const query = deferred<Awaited<ReturnType<typeof AppleHealth.getSleepSamples>>>();
    health.getSleepSamples.mockReturnValueOnce(query.promise);
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: 'Data Sources & Access' }));
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
    expect(screen.queryByText('Health connected with 0 imported sleep samples.')).not.toBeOnTheScreen();
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
      .press(screen.getByRole('button', { name: 'Data Sources & Access' }));
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
    await user.press(screen.getByRole('button', { name: 'Data Sources & Access' }));
    await user.press(screen.getByRole('button', { name: 'Connect to Health' }));

    await waitFor(() => expect(screen.getAllByText(/Health refresh failed/).length).toBeGreaterThan(0));
    expect(screen.queryByText('Health connected with 0 imported sleep samples.')).not.toBeOnTheScreen();
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
    await user.press(screen.getByRole('button', { name: 'Data Sources & Access' }));
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
    await user.press(screen.getByRole('button', { name: 'Data Sources & Access' }));
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
    await user.press(screen.getByRole('button', { name: 'Data Sources & Access' }));
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
    ['unsupported', 'Health unavailable'],
    ['denied', 'Health access denied'],
  ] as const)('keeps %s Health state visibly distinct', async (permissionStatus, expected) => {
    useStore.getState().setOnboarding({ permissionStatus });
    await render(<SleepScreen />);

    expect(screen.getByText(expected)).toBeOnTheScreen();
  });

  it('shows sample-data state distinctly from manual and Health states', async () => {
    useStore.setState({ demoMode: true });
    await render(<SleepScreen />);
    await userEvent.setup().press(screen.getByRole('button', { name: 'Data Sources & Access' }));

    expect(screen.getAllByText('Sample Data').length).toBeGreaterThan(0);
    expect(screen.getByText('Example sleep and caffeine data is active.')).toBeOnTheScreen();
  });

  it('shows timing metrics but withholds a pattern claim before 14 qualifying nights', async () => {
    useStore.setState({
      sleeps: [{ id: 'manual:sleep:timing', start: now - 8 * 60 * 60 * 1000, end: now, type: 'sleep' }],
      doses: [{ id: 'dose:timing', timestamp: now - 11 * 60 * 60 * 1000, mg: 80 }],
    });
    await render(<SleepScreen />);

    expect(screen.getByText('Last-dose timing')).toBeOnTheScreen();
    expect(screen.getByText('Typical range')).toBeOnTheScreen();
    expect(screen.getByText('Median sleep span')).toBeOnTheScreen();
    expect(screen.getByText('1/14 qualifying nights. Keep logging before reading a pattern.')).toBeOnTheScreen();
  });
});
