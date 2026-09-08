import React from 'react';
import { cleanup, render, screen } from '@testing-library/react-native';
import App from '~/App';
import { isUsingFallbackStorage } from '~/services/storage';
import { useStore } from '~/state/store';

jest.mock('react-native-safe-area-context', () => jest.requireActual('react-native-safe-area-context/jest/mock').default);
jest.mock('react-native-screens', () => ({ enableScreens: jest.fn() }));
jest.mock('react-native-gesture-handler', () => ({ GestureHandlerRootView: require('react-native').View }));
jest.mock('~/services/storage', () => ({
  ...jest.requireActual('~/services/storage'),
  isUsingFallbackStorage: jest.fn(),
}));
jest.mock('~/hooks/useAppInit', () => ({ useAppInit: () => true }));
jest.mock('~/navigation/RootNavigator', () => () => null);
jest.mock('~/screens/Onboarding/OnboardingScreen', () => () => null);
jest.mock('~/instrumentation/perf', () => ({}));

afterEach(cleanup);

it.each([false, true])('keeps a temporary storage alert visible with onboarding complete=%s', async (completed) => {
  jest.mocked(isUsingFallbackStorage).mockReturnValue(true);
  useStore.setState({ onboarding: { ...useStore.getState().onboarding, completed } });
  const app = await render(<App />);
  expect(screen.getByRole('alert', { name: /Temporary storage.*records disappear when you close.*manual logging/i })).toBeOnTheScreen();
  await app.rerender(<App />);
  expect(screen.getByRole('alert')).toBeOnTheScreen();
});

it('does not show a temporary storage warning when native storage works', async () => {
  jest.mocked(isUsingFallbackStorage).mockReturnValue(false);
  await render(<App />);
  expect(screen.queryByRole('alert')).not.toBeOnTheScreen();
});
