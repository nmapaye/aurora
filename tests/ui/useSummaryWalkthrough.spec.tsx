import type { RefObject } from 'react';
import {
  act,
  renderHook,
} from '@testing-library/react-native';
import {
  AccessibilityInfo,
  type LayoutChangeEvent,
  type ScrollView,
  type View,
} from 'react-native';
import * as Haptics from 'expo-haptics';

import useSummaryWalkthrough from '~/features/summaryWalkthrough/useSummaryWalkthrough';

jest.mock('expo-haptics', () => ({
  selectionAsync: jest.fn().mockResolvedValue(undefined),
}));

const scrollRef = {
  current: { scrollTo: jest.fn() },
} as unknown as RefObject<ScrollView | null>;
const contentRef = {
  current: {},
} as RefObject<View | null>;

function viewportEvent(height = 640) {
  return {
    nativeEvent: {
      layout: { x: 0, y: 0, width: 390, height },
    },
  } as LayoutChangeEvent;
}

describe('useSummaryWalkthrough', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    jest.spyOn(
      AccessibilityInfo,
      'isReduceMotionEnabled',
    ).mockResolvedValue(false);
    jest.spyOn(
      AccessibilityInfo,
      'addEventListener',
    ).mockReturnValue(
      { remove: jest.fn() } as unknown as ReturnType<
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

    await act(() => {
      result.current.onViewportLayout(viewportEvent());
    });
    await act(() => {
      jest.advanceTimersByTime(300);
    });
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(700);
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

    await act(() => {
      result.current.onSkip();
      result.current.onSkip();
    });

    expect(onComplete).toHaveBeenCalledTimes(1);
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

    await act(() => {
      result.current.onViewportLayout(viewportEvent());
    });
    await act(() => {
      jest.advanceTimersByTime(300);
    });
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(120);
    });

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

    await act(() => {
      result.current.onViewportLayout(viewportEvent());
    });
    await act(() => {
      jest.advanceTimersByTime(300);
    });
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(700);
    });

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
    const pinnedNode = {
      measureLayout: jest.fn(
        (
          _relativeTo: View,
          onSuccess: (
            x: number,
            y: number,
            width: number,
            height: number,
          ) => void,
        ) => onSuccess(0, 900, 390, 120),
      ),
    } as unknown as View;

    await act(() => {
      result.current.measureAnchor('pinned', pinnedNode);
      result.current.onViewportLayout(viewportEvent());
    });
    await act(() => {
      jest.advanceTimersByTime(300);
    });
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(120);
    });

    await act(() => {
      result.current.onPrimary();
    });
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(120);
    });

    expect(scrollRef.current?.scrollTo).toHaveBeenCalledWith({
      y: 876,
      animated: false,
    });
    expect(result.current.step.id).toBe('signals');
    expect(result.current.coachVisible).toBe(true);
  });
});
