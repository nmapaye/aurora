import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react-native';
import PlanningTargetsScreen from '~/screens/PlanningTargetsScreen';
import { defaultPlanningState } from '~/features/planning/model';
import { useStore } from '~/state/store';
jest.mock('~/navigation', () => ({ goBack: jest.fn(), navigate: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
beforeEach(() =>
  useStore.setState({
    planning: defaultPlanningState(),
    doses: [],
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  }),
);
it('persists reduction endpoints and reports excess budget without logging', async () => {
  await render(<PlanningTargetsScreen />);
  await fireEvent.changeText(screen.getByLabelText('Reduction days'), '3');
  await fireEvent.press(
    screen.getByRole('button', { name: 'Save reduction plan' }),
  );
  expect(useStore.getState().planning.reduction).toMatchObject({
    startMg: 200,
    endMg: 100,
    days: 3,
  });
  await fireEvent.changeText(
    screen.getByLabelText('Allocated caffeine mg'),
    '250',
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Allocate planned drink' }),
  );
  expect(screen.getByText(/50 mg over target/)).toBeOnTheScreen();
  expect(useStore.getState().doses).toHaveLength(0);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Remove allocation Coffee' }),
  );
  expect(useStore.getState().planning.budget.allocations).toHaveLength(0);
});
it('rejects one-day reductions and increasing targets', async () => {
  await render(<PlanningTargetsScreen />);
  await fireEvent.changeText(screen.getByLabelText('Reduction days'), '1');
  expect(
    screen.getByRole('button', { name: 'Save reduction plan' }),
  ).toBeDisabled();
  await fireEvent.changeText(screen.getByLabelText('Reduction days'), '14');
  await fireEvent.changeText(
    screen.getByLabelText('Ending daily caffeine mg'),
    '300',
  );
  expect(
    screen.getByRole('button', { name: 'Save reduction plan' }),
  ).toBeDisabled();
});
