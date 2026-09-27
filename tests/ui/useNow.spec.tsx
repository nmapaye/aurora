import React from 'react';
import { act, render, screen } from '@testing-library/react-native';
import { AppState, Text } from 'react-native';
import type { AppStateStatus } from 'react-native';

import useNow, { NOW_TICK_MS } from '~/hooks/useNow';

function Clock({ label }: { label: string }) {
  return <Text testID={label}>{useNow()}</Text>;
}

const start = new Date(2026, 8, 26, 9, 0, 0).getTime();

describe('useNow', () => {
  let onAppStateChange: ((state: AppStateStatus) => void) | null;
  const remove = jest.fn();
  // The RN test harness owns timers of its own, so a raw jest.getTimerCount()
  // can't isolate the hook's interval. Track only setInterval/clearInterval
  // calls scheduled at NOW_TICK_MS -- the hook's distinctive delay -- to
  // assert on the hook-owned timer's lifecycle specifically.
  let ownedTimerIds: Set<unknown>;

  const ownedTimerCount = () => ownedTimerIds.size;

  beforeEach(() => {
    jest.useFakeTimers({ now: start });
    onAppStateChange = null;
    remove.mockClear();
    jest
      .spyOn(AppState, 'addEventListener')
      .mockImplementation((_type, handler) => {
        onAppStateChange = handler as (state: AppStateStatus) => void;
        return { remove } as unknown as ReturnType<
          typeof AppState.addEventListener
        >;
      });

    ownedTimerIds = new Set();
    const realSetInterval = global.setInterval;
    const realClearInterval = global.clearInterval;
    jest
      .spyOn(global, 'setInterval')
      .mockImplementation((...args: Parameters<typeof setInterval>) => {
        const id = realSetInterval(...args);
        if (args[1] === NOW_TICK_MS) ownedTimerIds.add(id);
        return id;
      });
    jest
      .spyOn(global, 'clearInterval')
      .mockImplementation((...args: Parameters<typeof clearInterval>) => {
        ownedTimerIds.delete(args[0]);
        return realClearInterval(...args);
      });
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  const shown = (label: string) =>
    Number(screen.getByTestId(label).props.children);

  it('ticks every consumer together on one shared timer', async () => {
    await render(
      <>
        <Clock label="a" />
        <Clock label="b" />
      </>,
    );
    expect(shown('a')).toBe(start);
    expect(AppState.addEventListener).toHaveBeenCalledTimes(1);
    expect(ownedTimerCount()).toBe(1);

    await act(async () => {
      jest.advanceTimersByTime(NOW_TICK_MS);
    });
    expect(shown('a')).toBe(start + NOW_TICK_MS);
    expect(shown('b')).toBe(start + NOW_TICK_MS);
    expect(ownedTimerCount()).toBe(1);
  });

  it('pauses in the background and catches up on foreground', async () => {
    await render(<Clock label="a" />);
    expect(ownedTimerCount()).toBe(1);

    await act(async () => {
      onAppStateChange?.('background');
    });
    expect(ownedTimerCount()).toBe(0);

    jest.setSystemTime(start + 3 * 60 * 60 * 1000);
    await act(async () => {
      onAppStateChange?.('active');
    });
    expect(shown('a')).toBe(start + 3 * 60 * 60 * 1000);
    expect(ownedTimerCount()).toBe(1);
  });

  it('stops the timer and AppState listener after the last unmount', async () => {
    const { unmount } = await render(<Clock label="a" />);
    expect(ownedTimerCount()).toBe(1);
    await act(async () => {
      await unmount();
    });
    expect(ownedTimerCount()).toBe(0);
    expect(remove).toHaveBeenCalledTimes(1);
  });
});
