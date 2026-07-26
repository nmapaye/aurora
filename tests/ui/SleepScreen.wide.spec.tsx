import React from 'react';
import { render, screen } from '@testing-library/react-native';

import SleepScreen from '~/screens/SleepScreen';
import { useStore } from '~/state/store';

jest.mock('~/hooks/useAdaptiveLayout', () => ({
  __esModule: true,
  default: () => ({
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
  }),
}));
jest.mock('~/services/platform/health/appleHealth', () => ({
  __esModule: true,
  default: { isAvailable: jest.fn().mockResolvedValue(true), requestAuthorization: jest.fn(), getSleepSamples: jest.fn() },
  makeHealthSleepSessionId: ({ start, end }: { start: number; end: number }) => `healthkit:sleep:${start}:${end}`,
}));
jest.mock('~/hooks/useCaffeineCutoff', () => ({ __esModule: true, default: () => ({ nextCutoff: Date.now() + 4 * 60 * 60 * 1000 }) }));
jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

describe('SleepScreen wide layout', () => {
  beforeEach(() => {
    useStore.setState({
      doses: [], sleeps: [], demoMode: false,
      onboarding: { completed: true, source: 'manual', permissionStatus: 'idle', appWalkthroughCompleted: true, appWalkthroughStep: 9 },
      healthSync: { importedCount: 0 },
    });
  });

  it('keeps the chart primary while placing highlights beside it on a wide iPad window', async () => {
    await render(<SleepScreen />);

    expect(screen.getByTestId('sleep-wide-layout')).toBeOnTheScreen();
    expect(screen.queryByTestId('sleep-compact-layout')).not.toBeOnTheScreen();
    expect(screen.getByTestId('sleep-primary-column')).toHaveStyle({
      width: 600,
    });
    expect(screen.getByTestId('sleep-supporting-column')).toHaveStyle({
      width: 540,
    });
    expect(screen.getByText('Highlights')).toBeOnTheScreen();
  });
});
