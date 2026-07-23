import type { RefObject } from 'react';
import {
  act,
  renderHook,
} from '@testing-library/react-native';
import {
  AccessibilityInfo,
  type LayoutChangeEvent,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
  type ScrollView,
  type View,
} from 'react-native';
import * as Haptics from 'expo-haptics';

import useSummaryWalkthrough from '~/features/summaryWalkthrough/useSummaryWalkthrough';
import {
  WALKTHROUGH_REDUCED_MOTION_SETTLE_MS,
  WALKTHROUGH_REVEAL_SETTLE_MS,
  WALKTHROUGH_SCROLL_SETTLE_MS,
  WALKTHROUGH_START_DELAY_MS,
} from '~/features/summaryWalkthrough/model';

jest.mock('expo-haptics', () => ({
  selectionAsync: jest.fn().mockResolvedValue(undefined),
}));

const scrollRef = {
  current: { scrollTo: jest.fn() },
} as unknown as RefObject<ScrollView | null>;
const contentRef = {
  current: {},
} as RefObject<View | null>;
let removeReduceMotionListener: jest.Mock;

function viewportEvent(height = 640) {
  return {
    nativeEvent: {
      layout: { x: 0, y: 0, width: 390, height },
    },
  } as LayoutChangeEvent;
}

function scrollEvent(y: number) {
  return {
    nativeEvent: {
      contentOffset: { x: 0, y },
    },
  } as NativeSyntheticEvent<NativeScrollEvent>;
}

function anchorNode(y: number, height = 120) {
  return {
    measureLayout: jest.fn(
      (
        _relativeTo: View,
        onSuccess: (
          x: number,
          y: number,
          width: number,
          height: number,
        ) => void,
      ) => onSuccess(0, y, 390, height),
    ),
  } as unknown as View;
}

async function advanceToFirstCoach(
  result: { current: ReturnType<typeof useSummaryWalkthrough> },
  revealSettleMs = WALKTHROUGH_REVEAL_SETTLE_MS,
) {
  await act(() => {
    result.current.onViewportLayout(viewportEvent());
  });
  await act(() => {
    jest.advanceTimersByTime(WALKTHROUGH_START_DELAY_MS);
  });
  await act(() => {
    jest.runOnlyPendingTimers();
  });
  await act(() => {
    jest.advanceTimersByTime(revealSettleMs);
  });
}

async function advanceToNextCoach(
  result: { current: ReturnType<typeof useSummaryWalkthrough> },
) {
  await act(() => {
    result.current.onPrimary();
  });
  await act(() => {
    jest.runOnlyPendingTimers();
  });
  await act(() => {
    jest.advanceTimersByTime(WALKTHROUGH_REVEAL_SETTLE_MS);
  });
}

describe('useSummaryWalkthrough', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    removeReduceMotionListener = jest.fn();
    jest.spyOn(
      AccessibilityInfo,
      'isReduceMotionEnabled',
    ).mockResolvedValue(false);
    jest.spyOn(
      AccessibilityInfo,
      'addEventListener',
    ).mockReturnValue(
      { remove: removeReduceMotionListener } as unknown as ReturnType<
        typeof AccessibilityInfo.addEventListener
      >,
    );
    jest.spyOn(
      AccessibilityInfo,
      'announceForAccessibility',
    ).mockImplementation(() => {});
    jest.spyOn(
      AccessibilityInfo,
      'setAccessibilityFocus',
    ).mockImplementation(() => {});
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('waits for layout, reveals stage one, and exposes its coach', async () => {
    const onComplete = jest.fn();
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: true,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete,
      }),
    );

    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_START_DELAY_MS);
    });
    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      result.current.onViewportLayout(viewportEvent());
    });
    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_START_DELAY_MS - 1);
    });
    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      jest.advanceTimersByTime(1);
    });
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_REVEAL_SETTLE_MS - 1);
    });
    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      jest.advanceTimersByTime(1);
    });

    expect(result.current.coachVisible).toBe(true);
    expect(result.current.step.id).toBe('orientation');
    expect(result.current.isRevealed('header')).toBe(true);
    expect(
      AccessibilityInfo.announceForAccessibility,
    ).toHaveBeenCalledWith(
      'Your day at a glance. Aurora brings caffeine, sleep, and alertness together.',
    );
    expect(Haptics.selectionAsync).toHaveBeenCalledTimes(1);
  });

  it('persists completion before dismissing on Skip', async () => {
    let activeWhenCompleted = false;
    const onComplete = jest.fn(() => {
      activeWhenCompleted = result.current.active;
    });
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete,
      }),
    );

    await act(() => {
      result.current.onSkip();
      result.current.onSkip();
    });

    expect(onComplete).toHaveBeenCalledTimes(1);
    expect(activeWhenCompleted).toBe(true);
    expect(result.current.active).toBe(false);
    expect(result.current.isRevealed('recent')).toBe(true);
  });

  it('removes haptics and long settling when Reduce Motion is enabled', async () => {
    jest.mocked(
      AccessibilityInfo.isReduceMotionEnabled,
    ).mockResolvedValue(true);
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete: jest.fn(),
      }),
    );

    await advanceToFirstCoach(
      result,
      WALKTHROUGH_REDUCED_MOTION_SETTLE_MS,
    );

    expect(result.current.coachVisible).toBe(true);
    expect(result.current.reduceMotion).toBe(true);
    expect(Haptics.selectionAsync).not.toHaveBeenCalled();
  });

  it('does not repeat stage cues when Reduce Motion changes', async () => {
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete: jest.fn(),
      }),
    );

    await advanceToFirstCoach(result);

    const reduceMotionListener = jest.mocked(
      AccessibilityInfo.addEventListener,
    ).mock.calls[0]?.[1] as unknown as (enabled: boolean) => void;

    await act(() => {
      reduceMotionListener(true);
    });
    await act(() => {
      reduceMotionListener(false);
    });

    expect(
      AccessibilityInfo.announceForAccessibility,
    ).toHaveBeenCalledTimes(1);
    expect(Haptics.selectionAsync).toHaveBeenCalledTimes(1);
  });

  it('uses an immediate scroll for Reduce Motion', async () => {
    jest.mocked(
      AccessibilityInfo.isReduceMotionEnabled,
    ).mockResolvedValue(true);
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete: jest.fn(),
      }),
    );
    const pinnedNode = anchorNode(900);

    await act(() => {
      result.current.measureAnchor('pinned', pinnedNode);
    });
    await advanceToFirstCoach(
      result,
      WALKTHROUGH_REDUCED_MOTION_SETTLE_MS,
    );

    await act(() => {
      result.current.onPrimary();
    });
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_REDUCED_MOTION_SETTLE_MS);
    });

    expect(scrollRef.current?.scrollTo).toHaveBeenCalledWith({
      y: 876,
      animated: false,
    });
    expect(result.current.step.id).toBe('signals');
    expect(result.current.coachVisible).toBe(true);
  });

  it('settles one animated scroll per stage despite intermediate frames', async () => {
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete: jest.fn(),
      }),
    );

    await act(() => {
      result.current.measureAnchor('pinned', anchorNode(900));
    });
    await advanceToFirstCoach(result);
    jest.mocked(scrollRef.current!.scrollTo).mockClear();
    await act(() => {
      result.current.onPrimary();
    });

    await act(() => {
      jest.advanceTimersByTime(100);
      result.current.onScroll(scrollEvent(100));
    });
    await act(() => {
      jest.advanceTimersByTime(100);
      result.current.onScroll(scrollEvent(200));
    });
    await act(() => {
      jest.advanceTimersByTime(
        WALKTHROUGH_SCROLL_SETTLE_MS - 201,
      );
    });

    expect(result.current.isRevealed('pinned')).toBe(false);
    await act(() => {
      jest.advanceTimersByTime(1);
    });

    expect(scrollRef.current?.scrollTo).toHaveBeenCalledTimes(1);
    expect(result.current.isRevealed('pinned')).toBe(true);
    expect(result.current.coachVisible).toBe(false);
  });

  it('cancels positioning while disabled and restarts cleanly when re-enabled', async () => {
    const { result, rerender } = await renderHook(
      (enabled: boolean) =>
        useSummaryWalkthrough({
          enabled,
          hasAlert: false,
          isWideLayout: false,
          scrollRef,
          contentRef,
          onComplete: jest.fn(),
        }),
      { initialProps: true },
    );

    await act(() => {
      result.current.measureAnchor('pinned', anchorNode(900));
    });
    await advanceToFirstCoach(result);
    jest.mocked(scrollRef.current!.scrollTo).mockClear();
    await act(() => {
      result.current.onPrimary();
    });
    await act(() => {
      jest.advanceTimersByTime(100);
    });

    await rerender(false);
    await act(() => {
      jest.advanceTimersByTime(
        WALKTHROUGH_SCROLL_SETTLE_MS +
          WALKTHROUGH_REVEAL_SETTLE_MS,
      );
    });
    expect(result.current.coachVisible).toBe(false);

    await rerender(true);
    expect(result.current.isRevealed('pinned')).toBe(false);
    expect(result.current.coachVisible).toBe(false);
    expect(scrollRef.current?.scrollTo).toHaveBeenCalledTimes(2);

    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_SCROLL_SETTLE_MS - 1);
    });
    expect(result.current.isRevealed('pinned')).toBe(false);

    await act(() => {
      jest.advanceTimersByTime(1);
    });
    expect(result.current.isRevealed('pinned')).toBe(true);
    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_REVEAL_SETTLE_MS);
    });
    expect(result.current.coachVisible).toBe(true);
  });

  it('replaces animated positioning when Reduce Motion turns on', async () => {
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete: jest.fn(),
      }),
    );

    await act(() => {
      result.current.measureAnchor('pinned', anchorNode(900));
    });
    await advanceToFirstCoach(result);
    jest.mocked(scrollRef.current!.scrollTo).mockClear();
    jest.mocked(Haptics.selectionAsync).mockClear();
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout');
    const clearTimeoutSpy = jest.spyOn(global, 'clearTimeout');

    await act(() => {
      result.current.onPrimary();
    });
    const animatedTimerIndex = setTimeoutSpy.mock.calls.findIndex(
      ([, delay]) => delay === WALKTHROUGH_SCROLL_SETTLE_MS,
    );
    const animatedTimer =
      setTimeoutSpy.mock.results[animatedTimerIndex]?.value;

    await act(() => {
      jest.advanceTimersByTime(100);
    });
    const reduceMotionListener = jest.mocked(
      AccessibilityInfo.addEventListener,
    ).mock.calls[0]?.[1] as unknown as (enabled: boolean) => void;
    await act(() => {
      reduceMotionListener(true);
    });

    expect(clearTimeoutSpy).toHaveBeenCalledWith(animatedTimer);
    expect(scrollRef.current?.scrollTo).toHaveBeenNthCalledWith(1, {
      y: 876,
      animated: true,
    });
    expect(scrollRef.current?.scrollTo).toHaveBeenNthCalledWith(2, {
      y: 876,
      animated: false,
    });

    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(
        WALKTHROUGH_REDUCED_MOTION_SETTLE_MS - 1,
      );
    });
    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      jest.advanceTimersByTime(1);
    });
    expect(result.current.coachVisible).toBe(true);
    expect(result.current.reduceMotion).toBe(true);
    expect(Haptics.selectionAsync).not.toHaveBeenCalled();
  });

  it('keeps a newer Reduce Motion system event over the initial query', async () => {
    let resolveInitial!: (value: boolean) => void;
    const initialQuery = new Promise<boolean>((resolve) => {
      resolveInitial = resolve;
    });
    jest.mocked(
      AccessibilityInfo.isReduceMotionEnabled,
    ).mockReturnValue(initialQuery);
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete: jest.fn(),
      }),
    );
    const reduceMotionListener = jest.mocked(
      AccessibilityInfo.addEventListener,
    ).mock.calls[0]?.[1] as unknown as (enabled: boolean) => void;

    await act(() => {
      reduceMotionListener(true);
    });
    expect(result.current.reduceMotion).toBe(true);

    await act(() => {
      resolveInitial(false);
      return initialQuery;
    });

    expect(result.current.reduceMotion).toBe(true);
  });

  it('uses the measured Dynamic Type coach height for positioning', async () => {
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete: jest.fn(),
      }),
    );

    await act(() => {
      result.current.measureAnchor('pinned', anchorNode(300));
    });
    await advanceToFirstCoach(result);
    await act(() => {
      result.current.onCoachLayout(viewportEvent(300));
    });
    await act(() => {
      result.current.onPrimary();
    });

    expect(scrollRef.current?.scrollTo).toHaveBeenCalledWith({
      y: 276,
      animated: true,
    });
  });

  it('persists only once for duplicate Finish actions', async () => {
    const onComplete = jest.fn();
    const { result } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete,
      }),
    );

    await advanceToFirstCoach(result);
    await advanceToNextCoach(result);
    await advanceToNextCoach(result);
    await advanceToNextCoach(result);

    expect(result.current.step.id).toBe('explore');
    await act(() => {
      result.current.onPrimary();
      result.current.onPrimary();
    });

    expect(onComplete).toHaveBeenCalledTimes(1);
    expect(result.current.active).toBe(false);
  });

  it('removes its listener and timers on unmount', async () => {
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout');
    const clearTimeoutSpy = jest.spyOn(global, 'clearTimeout');
    const { result, unmount } = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete: jest.fn(),
      }),
    );

    await act(() => {
      result.current.onViewportLayout(viewportEvent());
    });
    expect(setTimeoutSpy).toHaveBeenCalledWith(
      expect.any(Function),
      WALKTHROUGH_START_DELAY_MS,
    );
    const startTimer = setTimeoutSpy.mock.results.at(-1)?.value;

    await unmount();

    expect(removeReduceMotionListener).toHaveBeenCalledTimes(1);
    expect(clearTimeoutSpy).toHaveBeenCalledWith(startTimer);
  });
});
