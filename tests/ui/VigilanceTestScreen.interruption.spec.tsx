import React from 'react';
import { AppState, type AppStateStatus } from 'react-native';
import { act, render, screen, fireEvent } from '@testing-library/react-native';
import VigilanceTestScreen from '~/screens/VigilanceTestScreen';
import { useStore } from '~/state/store';
jest.mock('~/navigation', () => ({ goBack: jest.fn() }));
let change: (state: AppStateStatus) => void;
const remove = jest.fn();
beforeEach(() => {
  jest.useFakeTimers();
  useStore.setState({ vigilanceSessions: [] });
  jest.spyOn(AppState, 'addEventListener').mockImplementation((_event, handler) => {
    change = handler; return { remove };
  });
});
afterEach(() => { jest.useRealTimers(); jest.restoreAllMocks(); });
it.each(['inactive', 'background'] as const)('discards a run interrupted by %s and requires an explicit restart', async state => {
  await render(<VigilanceTestScreen />);
  await fireEvent.press(screen.getByRole('button', { name: 'Start Test' }));
  await act(() => { change?.(state); jest.advanceTimersByTime(70_000); change?.('active'); });
  expect(useStore.getState().vigilanceSessions).toEqual([]);
  expect(screen.getByRole('alert')).toHaveTextContent(/Test interrupted/);
  await act(() => { jest.advanceTimersByTime(70_000); });
  expect(useStore.getState().vigilanceSessions).toEqual([]);
  await fireEvent.press(screen.getByRole('button', { name: 'Start Test' }));
  expect(screen.queryByRole('alert')).toBeNull();
  await act(() => { jest.advanceTimersByTime(60_100); });
  expect(useStore.getState().vigilanceSessions).toHaveLength(1);
});
it('keeps an already completed result after an app interruption', async () => {
  const view = await render(<VigilanceTestScreen />);
  await fireEvent.press(screen.getByRole('button', { name: 'Start Test' }));
  await act(() => { jest.advanceTimersByTime(60_100); });
  const sessions = useStore.getState().vigilanceSessions;
  await act(() => { change?.('background'); change?.('active'); });
  expect(useStore.getState().vigilanceSessions).toEqual(sessions);
  expect(screen.getByText('Session complete')).toBeOnTheScreen();
  await view.unmount();
  expect(remove).toHaveBeenCalled();
});
