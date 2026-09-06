import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react-native';
import PlanningScreen from '~/screens/PlanningScreen';
import ExperimentsScreen from '~/screens/ExperimentsScreen';
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
it('edits and saves a hypothetical dose without logging it', async () => {
  await render(<PlanningScreen />);
  await fireEvent.changeText(screen.getByLabelText('Scenario name'), 'Workday');
  await fireEvent.changeText(
    screen.getByLabelText('Planned drink name'),
    'Tea',
  );
  await fireEvent.changeText(
    screen.getByLabelText('Planned caffeine mg'),
    '70',
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Add hypothetical dose' }),
  );
  await fireEvent.press(screen.getByRole('button', { name: 'Save scenario' }));
  expect(useStore.getState().planning.scenarios[0].doses[0].mg).toBe(70);
  expect(useStore.getState().doses).toHaveLength(0);
  await fireEvent.press(screen.getByRole('button', { name: 'Delete Workday' }));
  expect(useStore.getState().planning.scenarios).toHaveLength(0);
});
it('records a subjective rating independently of vigilance tests', async () => {
  await render(<ExperimentsScreen />);
  await fireEvent.press(screen.getByRole('button', { name: 'Rating 4 of 5' }));
  await fireEvent.changeText(
    screen.getByLabelText('Check-in note'),
    'After lunch',
  );
  await fireEvent.press(screen.getByRole('button', { name: 'Save check-in' }));
  expect(useStore.getState().planning.checkIns[0]).toMatchObject({
    rating: 4,
    note: 'After lunch',
  });
});
it('disables saving during the walkthrough', async () => {
  useStore.setState({
    onboarding: {
      ...useStore.getState().onboarding,
      appWalkthroughCompleted: false,
    },
  });
  await render(<PlanningScreen />);
  expect(screen.getByRole('button', { name: 'Save scenario' })).toBeDisabled();
});
it('reopens and edits saved scenarios while sensitivity leaves preferences unchanged', async () => {
  useStore.setState({
    planning: {
      ...defaultPlanningState(),
      scenarios: [
        {
          id: 'a',
          name: 'Tea day',
          doses: [{ id: 'd', label: 'Tea', mg: 50, offsetMinutes: 60 }],
        },
      ],
    },
  });
  const halfLife = useStore.getState().prefs.halfLife;
  await render(<PlanningScreen />);
  await fireEvent.press(screen.getByRole('button', { name: 'Open Tea day' }));
  await fireEvent.press(
    screen.getByRole('button', { name: 'Edit planned Tea' }),
  );
  await fireEvent.changeText(
    screen.getByLabelText('Planned caffeine mg'),
    '80',
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Update hypothetical dose' }),
  );
  await fireEvent.press(screen.getByRole('button', { name: 'Save scenario' }));
  expect(useStore.getState().planning.scenarios).toHaveLength(1);
  expect(useStore.getState().planning.scenarios[0].doses[0].mg).toBe(80);
  await fireEvent.changeText(screen.getByLabelText('Half-life 1 hours'), '2');
  await fireEvent.press(
    screen.getByRole('button', { name: 'Apply sensitivity values' }),
  );
  expect(useStore.getState().planning.sensitivityHours[0]).toBe(2);
  expect(useStore.getState().prefs.halfLife).toBe(halfLife);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Show projection table' }),
  );
  expect(
    screen.getByRole('button', { name: 'Hide projection table' }),
  ).toBeOnTheScreen();
});
it('saves and removes experiment windows without synthesizing observations', async () => {
  await render(<ExperimentsScreen />);
  await fireEvent.changeText(
    screen.getByLabelText('Experiment question'),
    'Does earlier tea coincide with longer sleep?',
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Save experiment' }),
  );
  expect(useStore.getState().planning.experiments).toHaveLength(1);
  expect(screen.getAllByText(/Daily caffeine mean: No data/)).toHaveLength(2);
  await fireEvent.press(
    screen.getByRole('button', {
      name: 'Delete experiment Does earlier tea coincide with longer sleep?',
    }),
  );
  expect(useStore.getState().planning.experiments).toHaveLength(0);
});
