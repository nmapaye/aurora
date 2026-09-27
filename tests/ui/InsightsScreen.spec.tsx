import React from 'react';
import { fireEvent, render, screen, userEvent, within } from '@testing-library/react-native';
import { Share } from 'react-native';

import type { VigilanceSession } from '~/domain/vigilance';
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
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

const now = new Date(2026, 6, 24, 12, 0, 0, 0).getTime();
const day = (daysAgo: number, hour = 9) => new Date(2026, 6, 24 - daysAgo, hour, 0, 0, 0).getTime();

const session = (id: string, daysAgo: number, score: number): VigilanceSession => ({
  id,
  startedAt: day(daysAgo, 9),
  completedAt: day(daysAgo, 9) + 60_000,
  durationMs: 60_000,
  trialCount: 10,
  validReactionCount: 9,
  falseStartCount: 0,
  lapseCount: 1,
  medianReactionMs: 300,
  meanReactionMs: 300,
  fastestReactionMs: 240,
  reactionStdDevMs: 60,
  score,
  rating: 'Steady',
});

function setCompactLayout() {
  jest.mocked(useAdaptiveLayout).mockReturnValue({
    width: 390, height: 844, isPad: false, isWideLayout: false,
    isIpadWindowed: false, contentMaxWidth: 600, topChromeBuffer: 0,
    horizontalPadding: 16, leftColumnWidth: 358, rightColumnWidth: 358,
  });
}

function renderedText() {
  return screen.toJSON() ? JSON.stringify(screen.toJSON()) : '';
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

  it('leads with Caffeine Intake on 2W and keeps the settings affordance instead of Share', async () => {
    await render(<InsightsScreen />);

    expect(screen.getByText('Caffeine Intake')).toBeOnTheScreen();
    expect(screen.getByRole('tab', { name: 'Two weeks' })).toHaveProp('accessibilityState', { selected: true });
    expect(screen.getByRole('button', { name: 'Open settings' })).toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Share' })).not.toBeOnTheScreen();
  });

  it('averages recorded days only and names the count, period, and source', async () => {
    const user = userEvent.setup();
    await render(<InsightsScreen />);

    // One recorded day in 2W: 90 mg, not 90 / 14.
    expect(screen.getByText('90 mg')).toBeOnTheScreen();
    expect(screen.getByText(/^Average of 1 recorded day · 14 days · .* · Manual$/)).toBeOnTheScreen();

    await user.press(screen.getByRole('tab', { name: 'Month' }));
    expect(screen.getByText('80 mg')).toBeOnTheScreen();
    expect(screen.getByText(/^Average of 2 recorded days · 30 days/)).toBeOnTheScreen();
  });

  it('makes the chart inspectable, reading an empty day as no record', async () => {
    await render(<InsightsScreen />);
    const plot = screen.getByTestId('insights-bars-plot');

    expect(plot).toHaveProp('accessibilityRole', 'adjustable');
    expect(plot.props.accessibilityLabel).toContain('13 days with no record');
    // Defaults to the latest recorded day (yesterday), not an empty today.
    expect(plot.props.accessibilityValue.text).toMatch(/90 mg · 1 entry · Manual$/);

    await fireEvent(plot, 'accessibilityAction', { nativeEvent: { actionName: 'increment' } });
    expect(screen.getByTestId('insights-bars-plot').props.accessibilityValue.text).toMatch(/No record$/);
    expect(screen.getByTestId('insights-bars-plot').props.accessibilityValue.text).not.toMatch(/0 mg/);
  });

  it('keeps an empty range honest with no headline number or chart', async () => {
    useStore.setState({ doses: [], vigilanceSessions: [] });
    await render(<InsightsScreen />);

    expect(screen.getByText('No caffeine recorded in this range.')).toBeOnTheScreen();
    expect(screen.queryByTestId('insights-bars')).not.toBeOnTheScreen();
    expect(screen.queryByText(/mg\/day/)).not.toBeOnTheScreen();
    expect(screen.getByLabelText(/Caffeine intake, 14 days.*No caffeine recorded in this range/)).toBeOnTheScreen();
  });

  it('shows no comparison from sparse data, only what a comparison still needs', async () => {
    useStore.setState({
      doses: [
        { id: 'cur', timestamp: day(1), mg: 300 },
        { id: 'prev', timestamp: day(15), mg: 100 },
      ],
    });
    await render(<InsightsScreen />);

    expect(screen.queryByTestId('insights-trend')).not.toBeOnTheScreen();
    expect(screen.getByTestId('insights-trend-insufficient')).toHaveTextContent(/once each period has 7 recorded days/);
    expect(screen.queryByText(/%/)).not.toBeOnTheScreen();
  });

  it('describes a comparison when both periods have enough recorded days', async () => {
    const doses = [0, 1, 2, 3].flatMap((ago) => [
      { id: `cur-${ago}`, timestamp: day(ago), mg: 200 },
      { id: `prev-${ago}`, timestamp: day(ago + 7), mg: 100 },
    ]);
    useStore.setState({ doses });
    const user = userEvent.setup();
    await render(<InsightsScreen />);
    await user.press(screen.getByRole('tab', { name: 'Week' }));

    expect(screen.getByTestId('insights-trend')).toHaveTextContent(/About 100% higher than the previous 7 days/);
    expect(screen.getByTestId('insights-trend')).toHaveTextContent(/4 and 4 recorded days/);
  });

  it('shows no limit, adherence, reference line, or sleep schedule advice', async () => {
    await render(<InsightsScreen />);
    const text = renderedText();

    expect(text).not.toMatch(/Adherence|limit|streak|Suggested bedtime|Suggested wake|90-minute|Guidance|400 mg/i);
    expect(screen.queryByTestId('insights-bars-reference')).not.toBeOnTheScreen();
  });

  it('keeps Export off Insights', async () => {
    await render(<InsightsScreen />);

    expect(screen.queryByRole('button', { name: /Export/ })).not.toBeOnTheScreen();
    expect(renderedText()).not.toMatch(/CSV/);
  });

  describe('Reaction Test signal', () => {
    it('is a quiet empty row with a clear action when there is no test', async () => {
      await render(<InsightsScreen />);
      const card = screen.getByRole('button', { name: /^Reaction Test, No data/ });

      expect(within(card).getByText('Take Reaction Test')).toBeOnTheScreen();
      await userEvent.setup().press(card);
      expect(navigate).toHaveBeenCalledWith('VigilanceTest');
    });

    it('shows one test with its date and source, without baseline prominence', async () => {
      useStore.setState({ vigilanceSessions: [session('s1', 1, 72)] });
      await render(<InsightsScreen />);

      expect(screen.getByText('72')).toBeOnTheScreen();
      expect(screen.getByText('Yesterday · Recorded')).toBeOnTheScreen();
      expect(screen.getByText(/1 of 3 tests toward a baseline/)).toBeOnTheScreen();
      expect(screen.queryByText(/Baseline \d/)).not.toBeOnTheScreen();
      expect(screen.queryByText(/Reaction.*average|average score/i)).not.toBeOnTheScreen();

      await userEvent.setup().press(screen.getByRole('button', { name: 'Take Reaction Test' }));
      expect(navigate).toHaveBeenCalledWith('VigilanceTest');
    });

    it('states a baseline only once three tests exist', async () => {
      useStore.setState({ vigilanceSessions: [session('a', 5, 60), session('b', 3, 90), session('c', 1, 70)] });
      await render(<InsightsScreen />);

      expect(screen.getByText(/Baseline 70, median of 3 tests in the last 30 days/)).toBeOnTheScreen();
    });

    it('marks a sample test as Sample Data', async () => {
      useStore.setState({ vigilanceSessions: [session('demo:vigilance:1', 0, 70)] });
      await render(<InsightsScreen />);

      expect(screen.getByText('Sample Data')).toBeOnTheScreen();
    });
  });

  it('keeps time-of-day, drinks, and history behind Details', async () => {
    const user = userEvent.setup();
    await render(<InsightsScreen />);

    expect(screen.queryByText('Time of Day')).not.toBeOnTheScreen();
    expect(screen.queryByText('Drinks')).not.toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: /Show All Caffeine Data/ })).not.toBeOnTheScreen();

    await user.press(screen.getByRole('button', { name: /^Details/ }));

    expect(screen.getByText('Time of Day')).toBeOnTheScreen();
    expect(screen.getByText('Drinks')).toBeOnTheScreen();
    expect(screen.getByText('Coffee')).toBeOnTheScreen();
    // A time of day with no entries is not presented as 0 mg.
    expect(screen.queryByText('0 mg')).not.toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: /Show All Caffeine Data/ }));
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
