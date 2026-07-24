import React from 'react';
import { render, screen, userEvent, waitFor } from '@testing-library/react-native';

import AppleHealth from '~/services/platform/health/appleHealth';
import SleepScreen from '~/screens/SleepScreen';
import { useStore } from '~/state/store';

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

describe('SleepScreen', () => {
  beforeEach(() => {
    jest.spyOn(Date, 'now').mockReturnValue(now);
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
      healthSync: { importedCount: 0 },
    });
  });

  afterEach(() => jest.restoreAllMocks());

  it('presents the Health-style week/month hierarchy and honest empty chart', async () => {
    await render(<SleepScreen />);

    expect(screen.getAllByText('Sleep').length).toBeGreaterThan(0);
    expect(screen.getByRole('button', { name: 'Add Data' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'W' })).toHaveProp('accessibilityState', { selected: true });
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
    expect(screen.getByDisplayValue(String(now - 8 * 60 * 60 * 1000))).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Save' }));

    expect(useStore.getState().sleeps[0]).toMatchObject({
      id: expect.stringMatching(/^manual:sleep:/),
      type: 'sleep',
    });
    expect(screen.getByLabelText('Sleep session saved.')).toBeOnTheScreen();
  });

  it('shows a validation message and disables save when the end is in the future', async () => {
    const user = userEvent.setup();
    await render(<SleepScreen />);
    await user.press(screen.getByRole('button', { name: 'Add Data' }));
    await user.clear(screen.getByLabelText('End time'));
    await user.type(screen.getByLabelText('End time'), String(now + 1));

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
  });

  it.each([
    ['unsupported', 'Health unavailable'],
    ['denied', 'Health access denied'],
  ] as const)('keeps %s Health state visibly distinct', async (permissionStatus, expected) => {
    useStore.getState().setOnboarding({ permissionStatus });
    await render(<SleepScreen />);

    expect(screen.getByText(expected)).toBeOnTheScreen();
  });
});
