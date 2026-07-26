import type { RefObject } from 'react';
import { act, renderHook } from '@testing-library/react-native';
import {
  AccessibilityInfo,
  type LayoutChangeEvent,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
  type ScrollView,
  type View,
} from 'react-native';
import * as Haptics from 'expo-haptics';

import {
  WALKTHROUGH_REDUCED_MOTION_SETTLE_MS,
  WALKTHROUGH_REVEAL_SETTLE_MS,
  WALKTHROUGH_SCROLL_SETTLE_MS,
  WALKTHROUGH_START_DELAY_MS,
} from '~/features/appWalkthrough/model';
import useAppWalkthrough from '~/features/appWalkthrough/useAppWalkthrough';
import { useStore } from '~/state/store';

jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
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

function viewportEvent(height = 640, width = 390) {
  return {
    nativeEvent: {
      layout: { x: 0, y: 0, width, height },
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

function renderSummaryHook(isWideLayout = false) {
  return renderHook(
    ({ wide }: { wide: boolean }) =>
      useAppWalkthrough({
        route: 'Summary',
        isWideLayout: wide,
        scrollRef,
        contentRef,
      }),
    { initialProps: { wide: isWideLayout } },
  );
}

async function advanceToFirstCoach(
  result: { current: ReturnType<typeof useAppWalkthrough> },
  settleMs = WALKTHROUGH_REVEAL_SETTLE_MS,
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
    jest.advanceTimersByTime(settleMs);
  });
}

describe('useAppWalkthrough animated coordination', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    jest.mocked(scrollRef.current!.scrollTo).mockClear();
    removeReduceMotionListener = jest.fn();
    jest
      .spyOn(AccessibilityInfo, 'isReduceMotionEnabled')
      .mockResolvedValue(false);
    jest
      .spyOn(AccessibilityInfo, 'addEventListener')
      .mockReturnValue({
        remove: removeReduceMotionListener,
      } as unknown as ReturnType<typeof AccessibilityInfo.addEventListener>);
    jest
      .spyOn(AccessibilityInfo, 'announceForAccessibility')
      .mockImplementation(() => {});
    jest
      .spyOn(AccessibilityInfo, 'setAccessibilityFocus')
      .mockImplementation(() => {});
    useStore.setState({
      onboarding: {
        completed: true,
        source: 'manual',
        permissionStatus: 'unsupported',
        appWalkthroughCompleted: false,
        appWalkthroughStep: 0,
      },
    });
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('settles one normal animated scroll before revealing the next step', async () => {
    const { result } = await renderSummaryHook();
    await act(() => {
      result.current.measureAnchor('summary-pinned', anchorNode(900));
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
      jest.advanceTimersByTime(WALKTHROUGH_SCROLL_SETTLE_MS - 201);
    });

    expect(result.current.isRevealed('summary-pinned')).toBe(false);
    expect(result.current.locked).toBe(true);
    await act(() => {
      jest.advanceTimersByTime(1);
    });

    expect(scrollRef.current?.scrollTo).toHaveBeenCalledTimes(1);
    expect(scrollRef.current?.scrollTo).toHaveBeenCalledWith({
      y: 876,
      animated: true,
    });
    expect(result.current.isRevealed('summary-pinned')).toBe(true);
    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_REVEAL_SETTLE_MS);
    });
    expect(result.current.coachVisible).toBe(true);
  });

  it('replaces an animated settle when Reduce Motion turns on at runtime', async () => {
    const { result } = await renderSummaryHook();
    await act(() => {
      result.current.measureAnchor('summary-pinned', anchorNode(900));
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
    const animatedTimer = setTimeoutSpy.mock.results[animatedTimerIndex]?.value;

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
      jest.advanceTimersByTime(WALKTHROUGH_REDUCED_MOTION_SETTLE_MS);
    });
    expect(result.current.coachVisible).toBe(true);
    expect(result.current.reduceMotion).toBe(true);
    expect(Haptics.selectionAsync).not.toHaveBeenCalled();
  });

  it('cancels a stale settle when the viewport rotates during positioning', async () => {
    const { result } = await renderSummaryHook();
    await act(() => {
      result.current.measureAnchor('summary-pinned', anchorNode(900));
    });
    await advanceToFirstCoach(result);
    jest.mocked(scrollRef.current!.scrollTo).mockClear();
    const clearTimeoutSpy = jest.spyOn(global, 'clearTimeout');

    await act(() => {
      result.current.onPrimary();
    });
    await act(() => {
      jest.advanceTimersByTime(100);
      result.current.onViewportLayout(viewportEvent(500, 844));
    });

    expect(clearTimeoutSpy).toHaveBeenCalled();
    expect(scrollRef.current?.scrollTo).toHaveBeenCalledTimes(2);
    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_SCROLL_SETTLE_MS - 100);
    });
    expect(result.current.isRevealed('summary-pinned')).toBe(false);

    await act(() => {
      jest.advanceTimersByTime(100);
    });
    expect(result.current.isRevealed('summary-pinned')).toBe(true);
  });

  it('repositions the current step when compact layout becomes wide', async () => {
    const { result, rerender } = await renderSummaryHook();
    await advanceToFirstCoach(result);
    expect(result.current.coachVisible).toBe(true);

    await rerender({ wide: true });
    expect(result.current.coachVisible).toBe(false);
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_REVEAL_SETTLE_MS);
    });

    expect(result.current.step.id).toBe('summary-orientation');
    expect(result.current.coachVisible).toBe(true);
  });

  it('restarts positioning when the active anchor measurement changes', async () => {
    const { result } = await renderSummaryHook();
    await act(() => {
      result.current.measureAnchor('summary-pinned', anchorNode(900));
    });
    await advanceToFirstCoach(result);
    jest.mocked(scrollRef.current!.scrollTo).mockClear();

    await act(() => {
      result.current.onPrimary();
    });
    await act(() => {
      jest.advanceTimersByTime(100);
      result.current.measureAnchor('summary-pinned', anchorNode(500));
    });

    expect(scrollRef.current?.scrollTo).toHaveBeenNthCalledWith(1, {
      y: 876,
      animated: true,
    });
    expect(scrollRef.current?.scrollTo).toHaveBeenNthCalledWith(2, {
      y: 476,
      animated: true,
    });
  });

  it('repositions when the measured Dynamic Type coach height grows', async () => {
    const { result } = await renderSummaryHook();
    await act(() => {
      result.current.measureAnchor('summary-pinned', anchorNode(300));
      result.current.onCoachLayout(viewportEvent(100));
    });
    await advanceToFirstCoach(result);
    jest.mocked(scrollRef.current!.scrollTo).mockClear();

    await act(() => {
      result.current.onPrimary();
    });
    expect(scrollRef.current?.scrollTo).not.toHaveBeenCalled();

    await act(() => {
      result.current.onCoachLayout(viewportEvent(300));
    });

    expect(scrollRef.current?.scrollTo).toHaveBeenCalledWith({
      y: 276,
      animated: true,
    });
    expect(result.current.coachVisible).toBe(false);
  });

  it('does not duplicate announcements or haptics during geometry and motion changes', async () => {
    const { result, rerender } = await renderSummaryHook();
    await advanceToFirstCoach(result);

    const reduceMotionListener = jest.mocked(
      AccessibilityInfo.addEventListener,
    ).mock.calls[0]?.[1] as unknown as (enabled: boolean) => void;
    await act(() => {
      reduceMotionListener(true);
      reduceMotionListener(false);
    });
    await rerender({ wide: true });
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_REVEAL_SETTLE_MS);
    });

    expect(
      AccessibilityInfo.announceForAccessibility,
    ).toHaveBeenCalledTimes(1);
    expect(Haptics.selectionAsync).toHaveBeenCalledTimes(1);
  });

  it('cancels while globally complete and restarts if pending becomes active again', async () => {
    const { result } = await renderSummaryHook();
    await act(() => {
      result.current.measureAnchor('summary-pinned', anchorNode(900));
    });
    await advanceToFirstCoach(result);
    jest.mocked(scrollRef.current!.scrollTo).mockClear();
    await act(() => {
      result.current.onPrimary();
    });
    await act(() => {
      jest.advanceTimersByTime(100);
      useStore.setState((state) => ({
        onboarding: {
          ...state.onboarding,
          appWalkthroughCompleted: true,
        },
      }));
    });
    await act(() => {
      jest.advanceTimersByTime(
        WALKTHROUGH_SCROLL_SETTLE_MS + WALKTHROUGH_REVEAL_SETTLE_MS,
      );
    });
    expect(result.current.active).toBe(false);
    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      useStore.setState((state) => ({
        onboarding: {
          ...state.onboarding,
          appWalkthroughCompleted: false,
        },
      }));
    });
    expect(result.current.active).toBe(true);
    expect(result.current.coachVisible).toBe(false);
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_REVEAL_SETTLE_MS);
    });
    expect(result.current.coachVisible).toBe(true);
  });

  it('removes its Reduce Motion listener and pending start timer on unmount', async () => {
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout');
    const clearTimeoutSpy = jest.spyOn(global, 'clearTimeout');
    const { result, unmount } = await renderSummaryHook();

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
