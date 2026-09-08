import React from 'react';
import {
  act,
  cleanup,
  render,
  screen,
  userEvent,
  waitFor,
} from '@testing-library/react-native';

import OnboardingScreen from '~/screens/Onboarding/OnboardingScreen';
import SleepHistoryScreen from '~/screens/SleepHistoryScreen';
import SleepScreen from '~/screens/SleepScreen';
import AppleHealth from '~/services/platform/health/appleHealth';
import { requestHealthPermissions } from '~/services/permissions';
import { jsonStringStorage } from '~/services/storage';
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

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}

function importStatus() {
  return useStore.getState().healthSync.importStatus;
}

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
      message: 'Health request completed. Aurora will check for readable sleep samples.',
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
      healthSync: { importedCount: 0, importStatus: 'idle' },
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
    expect(importStatus()).toBe('succeeded');
    expect(screen.getByText('Status: Import completed')).toBeOnTheScreen();
    expect(screen.getByText(/review imported sleep/i)).toBeOnTheScreen();

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

  it('explains an empty readable import without claiming access was granted', async () => {
    jest.mocked(AppleHealth.getSleepSamples).mockResolvedValueOnce([]);
    await render(<OnboardingScreen />);
    const user = await openPermissions();
    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));
    expect(await screen.findByText('Status: No readable sleep data')).toBeOnTheScreen();
    expect(screen.getByText(/No recent readable sleep samples.*may be no records.*read access/i)).toBeOnTheScreen();
    expect(screen.queryByText(/access (is )?granted/i)).not.toBeOnTheScreen();
    expect(screen.queryByText(/review imported sleep/i)).not.toBeOnTheScreen();
    expect(importStatus()).toBe('succeeded');
    expect(useStore.getState().sleeps).toEqual([]);
  });

  it.each([
    ['query rejection', () => Promise.reject(new Error('Health database unavailable')), 'Health database unavailable'],
    ['malformed payload', () => Promise.resolve(undefined as never), 'invalid payload'],
  ])('keeps authorization granted but renders an error state for %s', async (_case, result, message) => {
    jest.mocked(AppleHealth.getSleepSamples).mockImplementationOnce(result);
    await render(<OnboardingScreen />);
    const user = await openPermissions();
    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));

    expect(
      await screen.findByRole('alert', {
        name: new RegExp(`Health request completed. Import failed.*${message}`, 'i'),
      }),
    ).toBeOnTheScreen();
    expect(screen.getByText('Status: Import failed')).toBeOnTheScreen();
    expect(screen.queryByText('Status: Import completed')).not.toBeOnTheScreen();
    expect(screen.queryByText(/review imported sleep/i)).not.toBeOnTheScreen();
    expect(useStore.getState().onboarding.permissionStatus).toBe('granted');
    expect(importStatus()).toBe('failed');
    expect(useStore.getState().healthSync.lastMessage).toMatch(/Health import failed/i);
    expect(useStore.getState().sleeps).toEqual([]);
  });

  it('shows Sample Data after choosing examples following a first-run import failure', async () => {
    jest.mocked(AppleHealth.getSleepSamples).mockRejectedValueOnce(new Error('Database unavailable'));
    await render(<OnboardingScreen />);
    const user = await openPermissions();
    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));
    expect(await screen.findByText('Status: Import failed')).toBeOnTheScreen();

    await user.press(screen.getByRole('button', { name: 'Load Sample Data' }));
    expect(useStore.getState().healthSync).toEqual({ importedCount: 0, importStatus: 'idle' });
    await cleanup();
    useStore.getState().completeAppWalkthrough();
    await render(<SleepScreen />);

    expect(screen.getByText('Sample Data')).toBeOnTheScreen();
    expect(screen.queryByText('Health refresh failed')).not.toBeOnTheScreen();
  });

  it('persists a failed import presentation across an onboarding remount', async () => {
    jest
      .mocked(AppleHealth.getSleepSamples)
      .mockRejectedValueOnce(new Error('Health database unavailable'));
    await render(<OnboardingScreen />);
    const user = await openPermissions();
    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));
    expect(await screen.findByText('Status: Import failed')).toBeOnTheScreen();

    await cleanup();
    await render(<OnboardingScreen />);
    await openPermissions();

    expect(screen.getByText('Status: Import failed')).toBeOnTheScreen();
    expect(
      screen.getByRole('alert', {
        name: /Health request completed. Import failed.*Health database unavailable/i,
      }),
    ).toBeOnTheScreen();
    expect(screen.queryByText('Status: Import completed')).not.toBeOnTheScreen();
    expect(screen.queryByText(/review imported sleep/i)).not.toBeOnTheScreen();
  });

  it('shows persisted importing state until a valid query succeeds', async () => {
    const query = deferred<(typeof sample)[]>();
    jest.mocked(AppleHealth.getSleepSamples).mockReturnValueOnce(query.promise);
    await render(<OnboardingScreen />);
    const user = await openPermissions();
    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));

    await waitFor(() => expect(importStatus()).toBe('importing'));
    expect(screen.getByText('Status: Importing')).toBeOnTheScreen();
    expect(screen.queryByText('Status: Import completed')).not.toBeOnTheScreen();
    expect(screen.queryByText(/review imported sleep/i)).not.toBeOnTheScreen();

    await act(() => query.resolve([sample]));

    await waitFor(() => expect(importStatus()).toBe('succeeded'));
    expect(screen.getByText('Status: Import completed')).toBeOnTheScreen();
    expect(screen.getByText(/review imported sleep/i)).toBeOnTheScreen();
  });

  it('recovers failed to importing to succeeded without claiming connection early', async () => {
    const retryQuery = deferred<(typeof sample)[]>();
    jest
      .mocked(AppleHealth.getSleepSamples)
      .mockRejectedValueOnce(new Error('Health database unavailable'))
      .mockReturnValueOnce(retryQuery.promise);
    await render(<OnboardingScreen />);
    const user = await openPermissions();
    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));
    expect(await screen.findByText('Status: Import failed')).toBeOnTheScreen();

    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));
    await waitFor(() => expect(importStatus()).toBe('importing'));
    expect(screen.getByText('Status: Importing')).toBeOnTheScreen();
    expect(screen.queryByText('Status: Import completed')).not.toBeOnTheScreen();
    expect(screen.queryByText(/review imported sleep/i)).not.toBeOnTheScreen();

    await act(() => retryQuery.resolve([sample]));

    await waitFor(() =>
      expect(screen.getByText('Status: Import completed')).toBeOnTheScreen(),
    );
    expect(importStatus()).toBe('succeeded');
    expect(screen.queryByRole('alert')).not.toBeOnTheScreen();
    expect(useStore.getState().onboarding.permissionStatus).toBe('granted');
    expect(useStore.getState().sleeps).toHaveLength(1);
  });

  it('does not present granted authorization as a completed import when lifecycle is idle', async () => {
    useStore.setState({
      onboarding: {
        ...useStore.getState().onboarding,
        permissionStatus: 'granted',
      },
    });
    await render(<OnboardingScreen />);
    await openPermissions();

    expect(screen.getByText('Status: Import pending')).toBeOnTheScreen();
    expect(screen.queryByText('Status: Import completed')).not.toBeOnTheScreen();
    expect(screen.queryByText(/review imported sleep/i)).not.toBeOnTheScreen();
  });

  it('remounts an interrupted persisted import as pending instead of importing forever', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          onboarding: {
            completed: false,
            source: 'healthkit',
            permissionStatus: 'granted',
            appWalkthroughCompleted: false,
            appWalkthroughStep: 0,
          },
          healthSync: {
            importedCount: 0,
            importStatus: 'importing',
            lastMessage: 'Importing recent sleep from Health.',
          },
        },
        version: 6,
      }),
    );
    await useStore.persist.rehydrate();
    await render(<OnboardingScreen />);
    await openPermissions();

    expect(screen.getByText('Status: Import pending')).toBeOnTheScreen();
    expect(
      screen.getByText('Health request completed. Recent sleep import is pending.'),
    ).toBeOnTheScreen();
    expect(screen.queryByText('Status: Importing')).not.toBeOnTheScreen();
    expect(screen.queryByText('Status: Import completed')).not.toBeOnTheScreen();
    expect(screen.queryByText(/review imported sleep/i)).not.toBeOnTheScreen();
  });
});
