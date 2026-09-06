import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react-native';
import InsightsExplorerScreen from '~/screens/InsightsExplorerScreen';
import { defaultPlanningState } from '~/features/planning/model';
import { useStore } from '~/state/store';
jest.mock('~/navigation', () => ({ navigate: jest.fn(), goBack: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
beforeEach(() =>
  useStore.setState({
    doses: [],
    sleeps: [],
    vigilanceSessions: [],
    planning: defaultPlanningState(),
    caffeine: { ...useStore.getState().caffeine, zeroDays: [] },
  }),
);
it('offers equivalent chart inspection controls and explains missing inputs', async () => {
  await render(<InsightsExplorerScreen />);
  expect(
    screen.getByRole('button', { name: 'Earlier inspection time' }),
  ).toBeOnTheScreen();
  await fireEvent.press(
    screen.getByRole('button', { name: 'Later inspection time' }),
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Explain modeled alertness' }),
  );
  expect(screen.getByText(/circadian rhythm/)).toBeOnTheScreen();
  expect(screen.getByText(/No personal events recorded/)).toBeOnTheScreen();
});
it('reveals all analysis sections and keeps gaps distinct from zero', async () => {
  await render(<InsightsExplorerScreen />);
  await fireEvent.press(screen.getByRole('button', { name: 'Patterns' }));
  expect(screen.getByText('Weekday comparison')).toBeOnTheScreen();
  expect(
    screen.getByText(/At least 5 paired sleep observations/),
  ).toBeOnTheScreen();
  await fireEvent.press(screen.getByRole('button', { name: 'Completeness' }));
  expect(screen.getAllByText(/Caffeine missing/).length).toBe(14);
  await fireEvent.press(screen.getByRole('button', { name: 'Weekly review' }));
  expect(screen.getByText(/7 of 7 days missing caffeine/)).toBeOnTheScreen();
  await fireEvent.press(screen.getByRole('button', { name: 'Tests' }));
  expect(screen.getByText('No completed personal tests.')).toBeOnTheScreen();
});
it('shows detailed recorded test metrics and the earlier-test baseline count', async () => {
  const now = Date.now();
  const t = {
    id: 'selected',
    startedAt: now - 60000,
    completedAt: now,
    durationMs: 60000,
    trialCount: 10,
    validReactionCount: 8,
    falseStartCount: 2,
    lapseCount: 2,
    medianReactionMs: 300,
    meanReactionMs: 310,
    fastestReactionMs: 200,
    reactionStdDevMs: 20,
    score: 70,
    rating: 'Steady' as const,
  };
  useStore.setState({
    vigilanceSessions: [
      t,
      ...[1, 2, 3].map((n) => ({
        ...t,
        id: `p${n}`,
        startedAt: now - n * 3600000 - 60000,
        completedAt: now - n * 3600000,
      })),
    ],
  });
  await render(<InsightsExplorerScreen />);
  await fireEvent.press(screen.getByRole('button', { name: 'Tests' }));
  await fireEvent.press(
    screen.getByRole('button', { name: /Inspect test .* selected/ }),
  );
  expect(
    screen.getByText(/10 trials; 8 valid reactions; 2 lapses; 2 false starts/),
  ).toBeOnTheScreen();
  expect(
    screen.getByText(/3 earlier eligible tests. Prior median 300 ms/),
  ).toBeOnTheScreen();
});
it.each([360, 900])(
  'maps chart endpoints to first and last samples at width %s',
  async (width) => {
    await render(<InsightsExplorerScreen />);
    const chart = screen.getByTestId('inspection-chart', {
      includeHiddenElements: true,
    });
    await fireEvent(chart, 'layout', {
      nativeEvent: { layout: { width, height: 160 } },
    });
    await fireEvent.press(chart, {
      nativeEvent: { locationX: (width * 290) / 300 },
    });
    expect(
      screen.getByRole('button', { name: 'Later inspection time' }),
    ).toBeDisabled();
    await fireEvent.press(chart, {
      nativeEvent: { locationX: (width * 10) / 300 },
    });
    expect(
      screen.getByRole('button', { name: 'Earlier inspection time' }),
    ).toBeDisabled();
  },
);
