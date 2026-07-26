import { act, renderHook, waitFor } from '@testing-library/react-native';
import { AccessibilityInfo } from 'react-native';

import useReduceMotion from '~/hooks/useReduceMotion';

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

describe('useReduceMotion', () => {
  afterEach(() => jest.restoreAllMocks());

  it('uses the queried system preference when no event races it', async () => {
    jest.spyOn(AccessibilityInfo, 'isReduceMotionEnabled').mockResolvedValue(false);
    jest.spyOn(AccessibilityInfo, 'addEventListener').mockReturnValue({
      remove: jest.fn(),
    } as unknown as ReturnType<typeof AccessibilityInfo.addEventListener>);

    const { result } = await renderHook(() => useReduceMotion());

    expect(result.current).toBe(false);
  });

  it('does not let a stale query overwrite a newer system event', async () => {
    const query = deferred<boolean>();
    let onChange: ((enabled: boolean) => void) | undefined;
    jest.spyOn(AccessibilityInfo, 'isReduceMotionEnabled').mockReturnValue(query.promise);
    jest.spyOn(AccessibilityInfo, 'addEventListener').mockImplementation(
      (_event, listener) => {
        onChange = listener as unknown as (enabled: boolean) => void;
        return { remove: jest.fn() } as unknown as ReturnType<
          typeof AccessibilityInfo.addEventListener
        >;
      },
    );
    const { result } = await renderHook(() => useReduceMotion());

    await act(() => onChange?.(false));
    expect(result.current).toBe(false);

    await act(() => query.resolve(true));
    expect(result.current).toBe(false);
  });

  it('keeps the conservative default when the query rejects', async () => {
    jest
      .spyOn(AccessibilityInfo, 'isReduceMotionEnabled')
      .mockRejectedValue(new Error('Unavailable'));
    jest.spyOn(AccessibilityInfo, 'addEventListener').mockReturnValue({
      remove: jest.fn(),
    } as unknown as ReturnType<typeof AccessibilityInfo.addEventListener>);

    const { result } = await renderHook(() => useReduceMotion());

    await waitFor(() => expect(result.current).toBe(true));
  });

  it('removes its subscription and ignores a late query after unmount', async () => {
    const query = deferred<boolean>();
    const remove = jest.fn();
    jest.spyOn(AccessibilityInfo, 'isReduceMotionEnabled').mockReturnValue(query.promise);
    jest.spyOn(AccessibilityInfo, 'addEventListener').mockReturnValue({
      remove,
    } as unknown as ReturnType<typeof AccessibilityInfo.addEventListener>);
    const { unmount } = await renderHook(() => useReduceMotion());

    await unmount();
    expect(remove).toHaveBeenCalledTimes(1);
    await act(() => query.resolve(false));
    expect(remove).toHaveBeenCalledTimes(1);
  });
});
