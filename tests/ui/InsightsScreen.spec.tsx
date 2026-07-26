import React from 'react';
import { render, screen, userEvent, waitFor } from '@testing-library/react-native';
import { Share } from 'react-native';

import InsightsScreen from '~/screens/InsightsScreen';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import { navigate } from '~/navigation';
import { useStore } from '~/state/store';

jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('@react-navigation/native', () => ({
  ...jest.requireActual('@react-navigation/native'),
  useRoute: () => ({ key: 'insights', name: 'Insights', params: undefined }),
}));
jest.mock('~/hooks/useAdaptiveLayout', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('~/hooks/useSleepGuidance', () => ({
  __esModule: true,
  default: () => ({ bedtime: Date.parse('2026-07-24T22:30:00.000Z'), wake: Date.parse('2026-07-25T06:30:00.000Z'), mgAtBed: 0 }),
}));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

const now = new Date(2026, 6, 24, 12, 0, 0, 0).getTime();
const day = (daysAgo: number, hour = 9) => new Date(2026, 6, 24 - daysAgo, hour, 0, 0, 0).getTime();

function setCompactLayout() {
  jest.mocked(useAdaptiveLayout).mockReturnValue({
    width: 390, height: 844, isPad: false, isWideLayout: false,
    isIpadWindowed: false, contentMaxWidth: 600, topChromeBuffer: 0,
    horizontalPadding: 16, leftColumnWidth: 358, rightColumnWidth: 358,
  });
}

describe('InsightsScreen', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(Date, 'now').mockReturnValue(now);
    jest.spyOn(Share, 'share').mockResolvedValue({ action: 'sharedAction' });
    setCompactLayout();
    useStore.setState({
      doses: [
        { id: 'recent', timestamp: day(1, 9), mg: 90, source: 'Espresso' },
        { id: 'month', timestamp: day(20, 14), mg: 70, source: 'Tea' },
      ],
      vigilanceSessions: [],
      prefs: { ...useStore.getState().prefs, dailyLimitMg: 400 },
      demoMode: false,
    });
  });

  afterEach(() => jest.restoreAllMocks());

  it('uses one caffeine-detail hierarchy with 2W selected, without Summary, Trends, or History controls', async () => {
    await render(<InsightsScreen />);

    expect(screen.getByText('Caffeine Intake')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: '2W' })).toHaveProp('accessibilityState', { selected: true });
    expect(screen.queryByRole('button', { name: 'Summary' })).not.toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Trends' })).not.toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'History' })).not.toBeOnTheScreen();
  });

  it('changes the selected headline, chart range, and trend content together', async () => {
    const user = userEvent.setup();
    await render(<InsightsScreen />);

    expect(screen.getByText('6 mg/day')).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'M' }));

    expect(screen.getByRole('button', { name: 'M' })).toHaveProp('accessibilityState', { selected: true });
    expect(screen.getByText('5 mg/day')).toBeOnTheScreen();
    expect(screen.getByText(/30 days/)).toBeOnTheScreen();
    expect(screen.getByText('Tea')).toBeOnTheScreen();
  });

  it('keeps an empty period honest and exposes its chart availability in the accessibility summary', async () => {
    useStore.setState({ doses: [], vigilanceSessions: [] });
    await render(<InsightsScreen />);

    expect(screen.getByText('No caffeine data for this range.')).toBeOnTheScreen();
    expect(screen.getByLabelText(/Caffeine intake, 14 days.*No caffeine data is available/)).toBeOnTheScreen();
  });

  it('shows readable Share and export failures and opens the focused caffeine history route', async () => {
    jest.spyOn(Share, 'share').mockRejectedValue(new Error('Share unavailable'));
    const user = userEvent.setup();
    await render(<InsightsScreen />);

    await user.press(screen.getByRole('button', { name: 'Share' }));
    await waitFor(() => expect(screen.getByText('Unable to share insights. Share unavailable')).toBeOnTheScreen());
    await user.press(screen.getByRole('button', { name: 'Export CSV' }));
    await waitFor(() => expect(screen.getByText('Unable to export insights. Share unavailable')).toBeOnTheScreen());
    await user.press(screen.getByRole('button', { name: 'Show All Data' }));
    expect(navigate).toHaveBeenCalledWith('CaffeineHistory');
  });

  it('uses an asymmetric primary-left layout on a wide iPad window', async () => {
    jest.mocked(useAdaptiveLayout).mockReturnValue({
      width: 1180, height: 820, isPad: true, isWideLayout: true,
      isIpadWindowed: false, contentMaxWidth: 1220, topChromeBuffer: 0,
      horizontalPadding: 20, leftColumnWidth: 600, rightColumnWidth: 540,
    });
    await render(<InsightsScreen />);

    expect(screen.getByTestId('insights-wide-layout')).toBeOnTheScreen();
    expect(screen.getByTestId('insights-primary-column')).toHaveStyle({ width: 600 });
    expect(screen.getByTestId('insights-supporting-column')).toHaveStyle({ width: 540 });
  });
});
