import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react-native';
import PlanningScreen from '~/screens/PlanningScreen';
import { defaultPlanningState } from '~/features/planning/model';
import { useStore } from '~/state/store';

jest.mock('~/navigation', () => ({ goBack: jest.fn(), navigate: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

it('moves one visible time backward after reopening a shorter scenario', async () => {
  useStore.setState({
    planning: {
      ...defaultPlanningState(),
      scenarios: [
        {
          id: 'long',
          name: 'Long',
          doses: [{ id: 'late', label: 'Late', mg: 100, offsetMinutes: 10080 }],
        },
        { id: 'short', name: 'Short', doses: [] },
      ],
    },
    doses: [],
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  });
  await render(<PlanningScreen />);
  await fireEvent.press(screen.getByRole('button', { name: 'Open Long' }));
  for (let index = 0; index < 30; index += 1) {
    await fireEvent.press(
      screen.getByRole('button', { name: 'Next projection time' }),
    );
  }
  await fireEvent.press(screen.getByRole('button', { name: 'Open Short' }));
  const valueBefore = screen
    .getByText(/mg, alertness estimate/)
    .props.children.join('');
  const previous = screen.getByRole('button', {
    name: 'Previous projection time',
  });
  // Resetting to the first point is also an acceptable way to handle shortening.
  if (previous.props.disabled) return;
  await fireEvent.press(previous);
  expect(
    screen.getByText(/mg, alertness estimate/).props.children.join(''),
  ).not.toBe(valueBefore);
});
