import React from 'react';
import {
  cleanup,
  render,
  screen,
  userEvent,
  within,
} from '@testing-library/react-native';

import OnboardingScreen from '~/screens/Onboarding/OnboardingScreen';
import AppleHealth from '~/services/platform/health/appleHealth';
import { requestHealthPermissions } from '~/services/permissions';
import { useStore } from '~/state/store';

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
    `healthkit:sleep:${start}:${end}`,
}));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

function targetSleep() {
  return useStore.getState().prefs.targetSleep;
}

describe('OnboardingScreen', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    useStore.setState({
      doses: [],
      sleeps: [],
      demoMode: false,
      prefs: { ...useStore.getState().prefs, targetSleep: 8 },
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
  });

  it('adjusts the sleep target in half hours within 5 to 10 and selects presets exactly', async () => {
    await render(<OnboardingScreen />);
    const user = userEvent.setup();

    expect(screen.getByRole('progressbar', { name: 'Setup progress' })).toHaveAccessibilityValue({
      now: 1,
      max: 3,
      text: 'Step 1 of 3',
    });
    await user.press(screen.getByRole('button', { name: 'Increase sleep target' }));
    expect(targetSleep()).toBe(8.5);
    expect(screen.getByRole('button', { name: '8 hours' })).not.toBeSelected();

    await user.press(screen.getByRole('button', { name: '9 hours' }));
    await user.press(screen.getByRole('button', { name: 'Increase sleep target' }));
    await user.press(screen.getByRole('button', { name: 'Increase sleep target' }));
    expect(targetSleep()).toBe(10);
    expect(screen.getByRole('button', { name: 'Increase sleep target' })).toBeDisabled();

    await user.press(screen.getByRole('button', { name: '7 hours' }));
    expect(targetSleep()).toBe(7);
    expect(screen.getByRole('button', { name: '7 hours' })).toBeSelected();
  });

  it('pins the primary action below the scrolling form on the stacked layout', async () => {
    await render(<OnboardingScreen />);
    const user = userEvent.setup();
    const actionBar = () => within(screen.getByTestId('onboarding-action-bar'));
    const form = () => within(screen.getByTestId('onboarding-scroll'));

    expect(screen.getByTestId('onboarding-stacked-layout')).toBeOnTheScreen();
    expect(actionBar().getByRole('button', { name: 'Continue' })).toBeOnTheScreen();
    expect(form().queryByRole('button', { name: 'Continue' })).not.toBeOnTheScreen();
    // The presets stay in the scrolling form, never under the bar.
    expect(form().getByRole('button', { name: '9 hours' })).toBeOnTheScreen();
    expect(actionBar().queryByRole('button', { name: '9 hours' })).not.toBeOnTheScreen();

    await user.press(actionBar().getByRole('button', { name: 'Continue' }));
    expect(actionBar().getByRole('button', { name: 'Back' })).toBeOnTheScreen();
    await user.press(actionBar().getByRole('button', { name: 'Continue' }));

    // Last step: Finish stays pinned; its explanation and the sample-data
    // option scroll with the step content.
    expect(actionBar().getByRole('button', { name: 'Finish setup' })).toBeOnTheScreen();
    expect(
      form().getByText('Connect Health, or finish with manual setup.'),
    ).toBeOnTheScreen();
    expect(
      form().getByRole('button', { name: 'Load Sample Data' }),
    ).toBeOnTheScreen();
    expect(actionBar().queryByText(/Connect Health/)).not.toBeOnTheScreen();
  });

  it('finishes manual setup without requesting Health and leaves the walkthrough to follow', async () => {
    await render(<OnboardingScreen />);
    const user = userEvent.setup();
    await user.press(screen.getByRole('button', { name: 'Continue' }));
    await user.press(screen.getByRole('button', { name: /Manual logging/ }));
    await user.press(screen.getByRole('button', { name: 'Continue' }));

    expect(screen.getByRole('header', { name: 'Ready for manual logging' })).toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Allow Health Access' })).not.toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Finish setup' }));

    expect(requestHealthPermissions).not.toHaveBeenCalled();
    expect(useStore.getState().onboarding).toMatchObject({
      completed: true,
      source: 'manual',
      permissionStatus: 'unsupported',
      appWalkthroughCompleted: false,
      appWalkthroughStep: 0,
    });
  });

  it('lets setup finish after an incomplete Health request without reading sleep', async () => {
    jest.mocked(requestHealthPermissions).mockResolvedValue({
      status: 'denied',
      message: 'Health access request did not complete.',
    });
    await render(<OnboardingScreen />);
    const user = userEvent.setup();
    await user.press(screen.getByRole('button', { name: 'Continue' }));
    await user.press(screen.getByRole('button', { name: 'Continue' }));

    expect(screen.getByText('Read-only')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Finish setup' })).toBeDisabled();
    await user.press(screen.getByRole('button', { name: 'Allow Health Access' }));

    expect(await screen.findByText('Status: Request incomplete')).toBeOnTheScreen();
    expect(
      screen.getByText('Health access wasn’t set up. You can still log sleep manually.'),
    ).toBeOnTheScreen();
    expect(AppleHealth.getSleepSamples).not.toHaveBeenCalled();
    await user.press(screen.getByRole('button', { name: 'Finish setup' }));
    expect(useStore.getState().onboarding).toMatchObject({
      completed: true,
      permissionStatus: 'denied',
    });
    expect(useStore.getState().sleeps).toEqual([]);
  });
});
