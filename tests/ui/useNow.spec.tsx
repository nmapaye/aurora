import { act, renderHook } from '@testing-library/react-native';
import { AppState, type AppStateStatus } from 'react-native';
import useNow from '~/hooks/useNow';

describe('useNow', () => {
  beforeEach(() => { jest.useFakeTimers(); jest.setSystemTime(1_700_000_000_000); });
  afterEach(() => { jest.useRealTimers(); jest.restoreAllMocks(); });

  it('refreshes an open screen and clears its interval on unmount', async () => {
    const remove = jest.fn();
    jest.spyOn(AppState, 'addEventListener').mockReturnValue({ remove });
    const schedule = jest.spyOn(global, 'setInterval');
    const cancel = jest.spyOn(global, 'clearInterval');
    const { result, unmount } = await renderHook(() => useNow(1000));
    const clockTimer = schedule.mock.results.at(-1)?.value;
    const initial = result.current;
    await act(() => jest.advanceTimersByTime(1000));
    expect(result.current).toBe(initial + 1000);
    await unmount();
    expect(remove).toHaveBeenCalledTimes(1);
    expect(cancel).toHaveBeenCalledWith(clockTimer);
  });

  it('refreshes immediately on foreground after the device clock changes', async () => {
    let listener: ((state: AppStateStatus) => void) | undefined;
    jest.spyOn(AppState, 'addEventListener').mockImplementation((_event, callback) => {
      listener = callback;
      return { remove: jest.fn() };
    });
    const { result } = await renderHook(() => useNow());
    jest.setSystemTime(1_700_100_000_000);
    await act(() => listener?.('active'));
    expect(result.current).toBe(1_700_100_000_000);
  });
});
