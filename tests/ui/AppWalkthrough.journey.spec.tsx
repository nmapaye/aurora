import type { RefObject } from 'react';
import { act, renderHook } from '@testing-library/react-native';
import {
  AccessibilityInfo,
  type LayoutChangeEvent,
  type ScrollView,
  type View,
} from 'react-native';
import * as Haptics from 'expo-haptics';

import {
  APP_WALKTHROUGH_STEPS,
  WALKTHROUGH_REDUCED_MOTION_SETTLE_MS,
  WALKTHROUGH_START_DELAY_MS,
  useAppWalkthrough,
  type AppWalkthroughRoute,
} from '~/features/appWalkthrough';
import { navigate } from '~/navigation';
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

const viewportEvent = {
  nativeEvent: {
    layout: { x: 0, y: 0, width: 390, height: 640 },
  },
} as LayoutChangeEvent;

async function settleCoach(
  result: { current: ReturnType<typeof useAppWalkthrough> },
) {
  await act(() => {
    result.current.onViewportLayout(viewportEvent);
  });
  await act(() => {
    jest.advanceTimersByTime(WALKTHROUGH_START_DELAY_MS);
  });
  await act(() => {
    jest.runOnlyPendingTimers();
  });
  await act(() => {
    jest.advanceTimersByTime(WALKTHROUGH_REDUCED_MOTION_SETTLE_MS);
  });
}

async function pressNextAndSettle(
  result: { current: ReturnType<typeof useAppWalkthrough> },
) {
  await act(() => {
    result.current.onPrimary();
  });
  await act(() => {
    jest.runOnlyPendingTimers();
  });
  await act(() => {
    jest.advanceTimersByTime(WALKTHROUGH_REDUCED_MOTION_SETTLE_MS);
  });
}

describe('app walkthrough journey coordinator', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    jest
      .spyOn(AccessibilityInfo, 'isReduceMotionEnabled')
      .mockResolvedValue(true);
    jest
      .spyOn(AccessibilityInfo, 'addEventListener')
      .mockReturnValue({
        remove: jest.fn(),
      } as unknown as ReturnType<typeof AccessibilityInfo.addEventListener>);
    jest
      .spyOn(AccessibilityInfo, 'announceForAccessibility')
      .mockImplementation(() => {});
    jest
      .spyOn(AccessibilityInfo, 'setAccessibilityFocus')
      .mockImplementation(() => {});
    jest
      .spyOn(require('react-native'), 'findNodeHandle')
      .mockReturnValue(99);
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

  it('persists all ten steps and navigates only at Summary, Sleep, and Log page boundaries', async () => {
    const { result, rerender } = await renderHook(
      ({ route }: { route: AppWalkthroughRoute }) =>
        useAppWalkthrough({
          route,
          isWideLayout: false,
          scrollRef,
          contentRef,
        }),
      { initialProps: { route: 'Summary' as AppWalkthroughRoute } },
    );

    await settleCoach(result);
    const observedProgress = [result.current.step.progress];

    for (let nextStep = 1; nextStep < APP_WALKTHROUGH_STEPS.length; nextStep += 1) {
      await pressNextAndSettle(result);
      const owner = APP_WALKTHROUGH_STEPS[nextStep].route;
      if (owner !== APP_WALKTHROUGH_STEPS[nextStep - 1].route) {
        await rerender({ route: owner });
        await settleCoach(result);
      }
      observedProgress.push(result.current.step.progress);
    }

    expect(observedProgress).toEqual([
      '1 of 10',
      '2 of 10',
      '3 of 10',
      '4 of 10',
      '5 of 10',
      '6 of 10',
      '7 of 10',
      '8 of 10',
      '9 of 10',
      '10 of 10',
    ]);
    expect(navigate).toHaveBeenCalledTimes(3);
    expect(navigate).toHaveBeenNthCalledWith(1, 'Sleep');
    expect(navigate).toHaveBeenNthCalledWith(2, 'Log');
    expect(navigate).toHaveBeenNthCalledWith(3, 'Insights');
    expect(useStore.getState().onboarding.appWalkthroughStep).toBe(9);
    expect(result.current.step.primaryAction).toBe('Finish');

    await act(() => {
      result.current.onPrimary();
    });
    expect(useStore.getState().onboarding.appWalkthroughCompleted).toBe(true);
  });

  it.each([
    [4, 'Sleep'],
    [6, 'Log'],
    [8, 'Insights'],
  ] as const)('resumes persisted step %i on its owning tab', async (stepIndex, route) => {
    useStore.setState({
      onboarding: {
        ...useStore.getState().onboarding,
        appWalkthroughStep: stepIndex,
      },
    });
    const { result } = await renderHook(() =>
      useAppWalkthrough({
        route,
        isWideLayout: false,
        scrollRef,
        contentRef,
      }),
    );

    await settleCoach(result);

    expect(result.current.active).toBe(true);
    expect(result.current.step).toEqual(APP_WALKTHROUGH_STEPS[stepIndex]);
    expect(result.current.coachVisible).toBe(true);
  });

  it('never starts before setup or for migrated-complete users', async () => {
    useStore.setState({
      onboarding: {
        ...useStore.getState().onboarding,
        completed: false,
      },
    });
    const first = await renderHook(() =>
      useAppWalkthrough({
        route: 'Summary',
        isWideLayout: false,
        scrollRef,
        contentRef,
      }),
    );

    await settleCoach(first.result);
    expect(first.result.current.active).toBe(false);
    await first.unmount();

    useStore.setState({
      onboarding: {
        ...useStore.getState().onboarding,
        completed: true,
        appWalkthroughCompleted: true,
      },
    });
    const migrated = await renderHook(() =>
      useAppWalkthrough({
        route: 'Summary',
        isWideLayout: false,
        scrollRef,
        contentRef,
      }),
    );
    await settleCoach(migrated.result);
    expect(migrated.result.current.active).toBe(false);
  });

  it('locks Next until missing-anchor positioning and reveal have settled', async () => {
    const { result } = await renderHook(() =>
      useAppWalkthrough({
        route: 'Summary',
        isWideLayout: false,
        scrollRef,
        contentRef,
      }),
    );

    await act(() => {
      result.current.onViewportLayout(viewportEvent);
    });
    expect(result.current.locked).toBe(true);
    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_START_DELAY_MS);
    });
    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_REDUCED_MOTION_SETTLE_MS);
    });

    expect(result.current.locked).toBe(false);
    expect(result.current.coachVisible).toBe(true);
  });

  it('completes globally from Skip on each owning screen', async () => {
    for (const [stepIndex, route] of [
      [0, 'Summary'],
      [4, 'Sleep'],
      [6, 'Log'],
      [8, 'Insights'],
    ] as const) {
      useStore.setState({
        onboarding: {
          ...useStore.getState().onboarding,
          appWalkthroughCompleted: false,
          appWalkthroughStep: stepIndex,
        },
      });
      const { result, unmount } = await renderHook(() =>
        useAppWalkthrough({
          route,
          isWideLayout: false,
          scrollRef,
          contentRef,
        }),
      );
      await settleCoach(result);
      await act(() => result.current.onSkip());
      expect(useStore.getState().onboarding.appWalkthroughCompleted).toBe(true);
      await unmount();
    }
  });

  it('honors Reduce Motion while announcing and focusing the resumed coach', async () => {
    useStore.setState({
      onboarding: {
        ...useStore.getState().onboarding,
        appWalkthroughStep: 8,
      },
    });
    const { result } = await renderHook(() =>
      useAppWalkthrough({
        route: 'Insights',
        isWideLayout: true,
        scrollRef,
        contentRef,
      }),
    );

    await settleCoach(result);

    expect(result.current.reduceMotion).toBe(true);
    expect(scrollRef.current?.scrollTo).not.toHaveBeenCalledWith(
      expect.objectContaining({ animated: true }),
    );
    expect(Haptics.selectionAsync).not.toHaveBeenCalled();
    expect(
      AccessibilityInfo.announceForAccessibility,
    ).toHaveBeenCalledWith(
      'See patterns over time. Change the range to compare caffeine, timing, and alertness.',
    );
    expect(AccessibilityInfo.setAccessibilityFocus).toHaveBeenCalledTimes(1);
  });

  it('remeasures and repositions the current coach when a window becomes wide', async () => {
    useStore.setState({
      onboarding: {
        ...useStore.getState().onboarding,
        appWalkthroughStep: 4,
      },
    });
    const { result, rerender } = await renderHook(
      ({ isWideLayout }: { isWideLayout: boolean }) =>
        useAppWalkthrough({
          route: 'Sleep',
          isWideLayout,
          scrollRef,
          contentRef,
        }),
      { initialProps: { isWideLayout: false } },
    );
    await settleCoach(result);
    expect(result.current.coachVisible).toBe(true);

    await rerender({ isWideLayout: true });
    expect(result.current.coachVisible).toBe(false);

    await act(() => {
      jest.runOnlyPendingTimers();
    });
    await act(() => {
      jest.advanceTimersByTime(WALKTHROUGH_REDUCED_MOTION_SETTLE_MS);
    });

    expect(result.current.step).toBe(APP_WALKTHROUGH_STEPS[4]);
    expect(result.current.coachVisible).toBe(true);
  });
});
