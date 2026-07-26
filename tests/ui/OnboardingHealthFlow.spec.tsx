import React from 'react';
import { cleanup, render, screen, userEvent, waitFor } from '@testing-library/react-native';

import OnboardingScreen from '~/screens/Onboarding/OnboardingScreen';
import SleepHistoryScreen from '~/screens/SleepHistoryScreen';
import SleepScreen from '~/screens/SleepScreen';
import AppleHealth from '~/services/platform/health/appleHealth';
import { requestHealthPermissions } from '~/services/permissions';
import { useStore } from '~/state/store';

jest.mock('@react-native-community/datetimepicker', () => {
  const React = require('react');
  const { View } = require('react-native');
  return { __esModule: true, default: (props: object) => React.createElement(View, props) };
});
jest.mock('~/services/permissions', () => ({
  requestHealthPermissions: jest.fn(),
}));
jest.mock('~/services/platform/health/appleHealth', () => ({
  __esModule: true,
  default: {
    isAvailable: jest.fn().mockResolvedValue(true),
    requestAuthorization: jest.fn().mockResolvedValue(true),
    getSleepSamples: jest.fn(),
  },
  makeHealthSleepSessionId: ({ start, end }: { start: number; end: number }) =>
    `healthkit:sleep:${Math.round(start)}:${Math.round(end)}`,
}));
jest.mock('~/hooks/useCaffeineCutoff', () => ({
  __esModule: true,
  default: () => ({ nextCutoff: Date.now() + 4 * 60 * 60 * 1000 }),
}));
jest.mock('~/navigation', () => ({ goBack: jest.fn(), navigate: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

const now = Date.parse('2026-07-24T12:00:00.000Z');
const sample = {
  start: Date.parse('2026-07-24T00:00:00.000Z'),
  end: Date.parse('2026-07-24T08:00:00.000Z'),
};

async function openPermissions() {
  const user = userEvent.setup();
  await user.press(screen.getByRole('button', { name: 'Continue' }));
  await user.press(screen.getByRole('button', { name: 'Continue' }));
  return user;
}

describe('onboarding Health import flow', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(Date, 'now').mockReturnValue(now);
    jest.mocked(requestHealthPermissions).mockResolvedValue({
      status: 'granted',
      message: 'Health access granted. Aurora can now import recent sleep.',
    });
    jest.mocked(AppleHealth.getSleepSamples).mockResolvedValue([sample]);
    useStore.setState({
      doses: [],
      sleeps: [],
      demoMode: false,
      onboarding: {
        completed: false,
        source: 'healthkit',
        permissionStatus: 'idle',
        appWalkthroughCompleted: false,
        appWalkthroughStep: 0,
      },
      healthSync: { importedCount: 0 },
    });
  });

  afterEach(async () => {
    await cleanup();
    jest.restoreAllMocks();
  });

  it('keeps an onboarding import labeled Health and deduped after a later refresh', async () => {
    await render(<OnboardingScreen />);
    const user = await openPermissions();
    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));

    await waitFor(() =>
      expect(useStore.getState().sleeps).toEqual([
        {
          id: `healthkit:sleep:${sample.start}:${sample.end}`,
          ...sample,
          type: 'sleep',
        },
      ]),
    );
    await waitFor(() =>
      expect(useStore.getState().healthSync.lastMessage).toBe(
        'Imported 1 recent sleep sample from Health.',
      ),
    );

    await cleanup();
    await render(<SleepHistoryScreen />);
    expect(screen.getByText('Health')).toBeOnTheScreen();
    expect(screen.queryByText('Manual')).not.toBeOnTheScreen();

    await cleanup();
    useStore.getState().setOnboarding({
      completed: true,
      appWalkthroughCompleted: true,
    });
    await render(<SleepScreen />);
    const sleepUser = userEvent.setup();
    await sleepUser.press(screen.getByRole('button', { name: 'Data Sources & Access' }));
    await sleepUser.press(screen.getByRole('button', { name: 'Refresh Sleep' }));

    await waitFor(() => expect(AppleHealth.getSleepSamples).toHaveBeenCalledTimes(2));
    expect(useStore.getState().sleeps).toHaveLength(1);
  });

  it.each([
    ['query rejection', () => Promise.reject(new Error('Health database unavailable')), 'Health database unavailable'],
    ['malformed payload', () => Promise.resolve(undefined as never), 'invalid payload'],
  ])('keeps authorization granted but shows a visible import error for %s', async (_case, result, message) => {
    jest.mocked(AppleHealth.getSleepSamples).mockImplementationOnce(result);
    await render(<OnboardingScreen />);
    const user = await openPermissions();
    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));

    await waitFor(() => expect(screen.getByText(new RegExp(message, 'i'))).toBeOnTheScreen());
    expect(screen.getByText('Status: Connected')).toBeOnTheScreen();
    expect(useStore.getState().onboarding.permissionStatus).toBe('granted');
    expect(useStore.getState().healthSync.lastMessage).toMatch(/Health import failed/i);
    expect(useStore.getState().sleeps).toEqual([]);
  });
});
