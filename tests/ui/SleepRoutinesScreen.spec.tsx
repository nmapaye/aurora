import React from 'react';
import { render, screen, fireEvent, act } from '@testing-library/react-native';
import SleepRoutinesScreen from '~/screens/SleepRoutinesScreen';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
import { useStore } from '~/state/store';
jest.mock('~/navigation', () => ({ goBack: jest.fn(), navigate: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
beforeEach(() => {
  useStore.setState({
    sleepRoutines: defaultSleepRoutines(8),
    sleeps: [],
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  });
});
it('keeps timer separate until the finished nap is confirmed', async () => {
  await render(<SleepRoutinesScreen />);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Start nap timer' }),
  );
  expect(useStore.getState().sleeps).toHaveLength(0);
  const start = useStore.getState().sleepRoutines.timer!.start;
  await act(() =>
    useStore.setState({
      sleepRoutines: {
        ...useStore.getState().sleepRoutines,
        timer: { start: start - 60000 },
      },
    }),
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Finish nap timer' }),
  );
  expect(useStore.getState().sleeps).toHaveLength(0);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Confirm nap entry' }),
  );
  expect(useStore.getState().sleeps[0].type).toBe('nap');
});
it('disables routine changes during walkthrough', async () => {
  useStore.setState({
    onboarding: {
      ...useStore.getState().onboarding,
      appWalkthroughCompleted: false,
    },
  });
  await render(<SleepRoutinesScreen />);
  expect(
    screen.getByRole('button', { name: 'Start nap timer' }),
  ).toBeDisabled();
  expect(
    screen.getByRole('button', { name: 'Add schedule exception' }),
  ).toBeDisabled();
});
it('saves weekday wall times through the native picker', async () => {
  await render(<SleepRoutinesScreen />);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Edit Monday sleep schedule' }),
  );
  await fireEvent.press(screen.getByRole('button', { name: 'Bedtime 22:30' }));
  await fireEvent(screen.getByTestId('routine-time-picker'), 'onChange', {
    nativeEvent: { timestamp: new Date('2026-09-07T21:15:00').getTime() },
  });
  await fireEvent.press(screen.getByRole('button', { name: 'Save' }));
  expect(useStore.getState().sleepRoutines.weekly[1].bedtime).toBe(1275);
  expect(useStore.getState().sleepRoutines.weekly[0].bedtime).toBe(1350);
});
it('restores a finished nap without adding sleep until confirmation', async () => {
  const start = Date.now() - 3600000,
    end = Date.now() - 1000;
  useStore.setState({
    sleepRoutines: { ...defaultSleepRoutines(8), timer: { start, end } },
  });
  await render(<SleepRoutinesScreen />);
  expect(
    screen.getByRole('button', { name: 'Confirm nap entry' }),
  ).toBeOnTheScreen();
  expect(useStore.getState().sleeps).toHaveLength(0);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Cancel nap timer' }),
  );
  expect(useStore.getState().sleepRoutines.timer).toBeNull();
  expect(useStore.getState().sleeps).toHaveLength(0);
});
it('speaks both weekday times and the wake date relationship', async () => {
  await render(<SleepRoutinesScreen />);
  expect(
    screen.getByRole('button', { name: 'Edit Monday sleep schedule' }).props
      .accessibilityValue.text,
  ).toBe('Bedtime 22:30, wake 06:30 next day');
});
