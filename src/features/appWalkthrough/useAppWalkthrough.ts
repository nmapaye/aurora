import {
  useCallback,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
} from 'react';
import type { RefObject } from 'react';
import {
  AccessibilityInfo,
  findNodeHandle,
} from 'react-native';
import type {
  LayoutChangeEvent,
  NativeScrollEvent,
  NativeSyntheticEvent,
  ScrollView,
  Text,
  View,
} from 'react-native';
import * as Haptics from 'expo-haptics';

import { navigate } from '~/navigation';
import { useStore } from '~/state/store';
import { spacing } from '~/theme/tokens';
import {
  APP_WALKTHROUGH_STEPS,
  clampAppWalkthroughStep,
  getRevealedGroups,
  getTargetScrollY,
  initialAppWalkthroughState,
  isAppWalkthroughPending,
  isTargetFullyVisible,
  reduceAppWalkthrough,
  WALKTHROUGH_REDUCED_MOTION_SETTLE_MS,
  WALKTHROUGH_REVEAL_SETTLE_MS,
  WALKTHROUGH_SCROLL_SETTLE_MS,
  WALKTHROUGH_START_DELAY_MS,
  WALKTHROUGH_TOP_CLEARANCE,
} from './model';
import type {
  AppWalkthroughAnchor,
  AppWalkthroughRevealGroup,
  AppWalkthroughRoute,
} from './model';

type AnchorMeasurement = { y: number; height: number };
type ViewportMeasurement = { width: number; height: number };

const WALKTHROUGH_COACH_FALLBACK_CLEARANCE = 180;
const GEOMETRY_EPSILON = 0.5;

function geometryValueChanged(previous: number, next: number) {
  return Math.abs(previous - next) >= GEOMETRY_EPSILON;
}

type Options = {
  route: AppWalkthroughRoute;
  isWideLayout: boolean;
  scrollRef: RefObject<ScrollView | null>;
  contentRef: RefObject<View | null>;
};

export default function useAppWalkthrough({
  route,
  isWideLayout,
  scrollRef,
  contentRef,
}: Options) {
  const onboarding = useStore((state) => state.onboarding);
  const advanceAppWalkthrough = useStore(
    (state) => state.advanceAppWalkthrough,
  );
  const completeAppWalkthrough = useStore(
    (state) => state.completeAppWalkthrough,
  );
  const persistedStep = clampAppWalkthroughStep(
    onboarding.appWalkthroughStep,
  );
  const [state, dispatch] = useReducer(reduceAppWalkthrough, {
    ...initialAppWalkthroughState,
    stepIndex: persistedStep,
  });
  const [reduceMotion, setReduceMotion] = useState<boolean | null>(null);
  const [geometryRevision, setGeometryRevision] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(0);
  const viewportHeightRef = useRef(0);
  const viewportRef = useRef<ViewportMeasurement>({
    width: 0,
    height: 0,
  });
  const scrollYRef = useRef(0);
  const firstRouteStep = APP_WALKTHROUGH_STEPS.find(
    (step) => step.route === route,
  );
  const anchorsRef = useRef<
    Partial<Record<AppWalkthroughAnchor, AnchorMeasurement>>
  >(firstRouteStep ? { [firstRouteStep.anchor]: { y: 0, height: 1 } } : {});
  const coachHeightRef = useRef(0);
  const scrollViewRef = useRef(scrollRef);
  const coachHeadingRef = useRef<Text | null>(null);
  const settleTimerRef = useRef<ReturnType<typeof setTimeout> | null>(
    null,
  );
  const startTimerRef = useRef<ReturnType<typeof setTimeout> | null>(
    null,
  );
  const completedRef = useRef(false);
  const announcedStepsRef = useRef(new Set<number>());
  const isWideLayoutRef = useRef(isWideLayout);

  scrollViewRef.current = scrollRef;

  const currentStep = APP_WALKTHROUGH_STEPS[state.stepIndex];
  const pending = isAppWalkthroughPending(onboarding);
  const enabled = pending && currentStep.route === route;

  const markGeometryChanged = useCallback(() => {
    setGeometryRevision((current) => current + 1);
    dispatch({ type: 'GEOMETRY_CHANGED' });
  }, []);

  useEffect(() => {
    if (state.stepIndex === persistedStep) return;
    dispatch({ type: 'SYNC', stepIndex: persistedStep });
  }, [persistedStep, state.stepIndex]);

  useEffect(() => {
    if (!enabled) {
      setReduceMotion(true);
      return;
    }

    let alive = true;
    let receivedSystemEvent = false;
    const onReduceMotionChanged = (value: boolean) => {
      receivedSystemEvent = true;
      if (alive) setReduceMotion(value);
    };

    AccessibilityInfo.isReduceMotionEnabled()
      .then((value) => {
        if (alive && !receivedSystemEvent) setReduceMotion(value);
      })
      .catch(() => {
        if (alive && !receivedSystemEvent) setReduceMotion(true);
      });
    const subscription = AccessibilityInfo.addEventListener(
      'reduceMotionChanged',
      onReduceMotionChanged,
    );
    return () => {
      alive = false;
      subscription.remove();
    };
  }, [enabled]);

  useEffect(() => {
    if (
      !enabled ||
      reduceMotion === null ||
      viewportHeight <= 0 ||
      state.phase !== 'waiting'
    ) {
      return;
    }

    const startTimer = setTimeout(() => {
      dispatch({ type: 'START' });
    }, WALKTHROUGH_START_DELAY_MS);
    startTimerRef.current = startTimer;

    return () => {
      clearTimeout(startTimer);
      if (startTimerRef.current === startTimer) {
        startTimerRef.current = null;
      }
    };
  }, [enabled, reduceMotion, state.phase, viewportHeight]);

  useEffect(() => {
    if (isWideLayoutRef.current === isWideLayout) return;
    isWideLayoutRef.current = isWideLayout;
    markGeometryChanged();
  }, [isWideLayout, markGeometryChanged]);

  useEffect(() => {
    if (
      !enabled ||
      state.phase !== 'positioning' ||
      reduceMotion === null
    ) {
      return;
    }

    const target = anchorsRef.current[currentStep.anchor];
    const currentViewportHeight = viewportHeightRef.current;
    let shouldAnimateScroll = false;
    if (target && currentViewportHeight > 0) {
      const measuredCoachHeight = coachHeightRef.current;
      const visible = isTargetFullyVisible({
        targetY: target.y,
        targetHeight: target.height,
        scrollY: scrollYRef.current,
        viewportHeight: currentViewportHeight,
        topClearance: WALKTHROUGH_TOP_CLEARANCE,
        bottomClearance:
          measuredCoachHeight > 0
            ? measuredCoachHeight + spacing.sm
            : WALKTHROUGH_COACH_FALLBACK_CLEARANCE,
      });
      const targetScrollY = getTargetScrollY(
        target.y,
        WALKTHROUGH_TOP_CLEARANCE,
      );
      const alreadyAtTarget = !geometryValueChanged(
        scrollYRef.current,
        targetScrollY,
      );
      if (!visible && !alreadyAtTarget) {
        shouldAnimateScroll = !reduceMotion;
        scrollViewRef.current.current?.scrollTo({
          y: targetScrollY,
          animated: !reduceMotion,
        });
      }
    }

    const settleTimer = setTimeout(
      () => dispatch({ type: 'POSITIONED' }),
      shouldAnimateScroll ? WALKTHROUGH_SCROLL_SETTLE_MS : 0,
    );
    settleTimerRef.current = settleTimer;

    return () => {
      clearTimeout(settleTimer);
      if (settleTimerRef.current === settleTimer) {
        settleTimerRef.current = null;
      }
    };
  }, [
    currentStep.anchor,
    enabled,
    geometryRevision,
    reduceMotion,
    state.phase,
  ]);

  useEffect(() => {
    if (!enabled || state.phase !== 'revealing' || reduceMotion === null) {
      return;
    }

    const settleTimer = setTimeout(
      () => dispatch({ type: 'SETTLED' }),
      reduceMotion
        ? WALKTHROUGH_REDUCED_MOTION_SETTLE_MS
        : WALKTHROUGH_REVEAL_SETTLE_MS,
    );
    settleTimerRef.current = settleTimer;

    return () => {
      clearTimeout(settleTimer);
      if (settleTimerRef.current === settleTimer) {
        settleTimerRef.current = null;
      }
    };
  }, [enabled, reduceMotion, state.phase]);

  useEffect(() => {
    if (
      !enabled ||
      state.phase !== 'coaching' ||
      announcedStepsRef.current.has(state.stepIndex)
    ) {
      return;
    }
    announcedStepsRef.current.add(state.stepIndex);

    try {
      AccessibilityInfo.announceForAccessibility(
        `${currentStep.title}. ${currentStep.body}`,
      );
      const handle = findNodeHandle(coachHeadingRef.current);
      if (handle) AccessibilityInfo.setAccessibilityFocus(handle);
    } catch {}
    if (reduceMotion === false) {
      Haptics.selectionAsync().catch(() => {});
    }
  }, [
    currentStep.body,
    currentStep.title,
    enabled,
    reduceMotion,
    state.phase,
    state.stepIndex,
  ]);

  useEffect(
    () => () => {
      if (settleTimerRef.current) clearTimeout(settleTimerRef.current);
      if (startTimerRef.current) clearTimeout(startTimerRef.current);
    },
    [],
  );

  const measureAnchor = useCallback(
    (id: AppWalkthroughAnchor, node: View | null) => {
      if (!node || !contentRef.current) return;
      node.measureLayout(
        contentRef.current,
        (_x, y, _width, height) => {
          const current = anchorsRef.current[id];
          if (
            current &&
            !geometryValueChanged(current.y, y) &&
            !geometryValueChanged(current.height, height)
          ) {
            return;
          }
          anchorsRef.current = {
            ...anchorsRef.current,
            [id]: { y, height },
          };
          markGeometryChanged();
        },
        () => {},
      );
    },
    [contentRef, markGeometryChanged],
  );

  const onViewportLayout = useCallback(
    (event: LayoutChangeEvent) => {
      const width = event.nativeEvent.layout.width;
      const height = event.nativeEvent.layout.height;
      const previous = viewportRef.current;
      const changed =
        geometryValueChanged(previous.width, width) ||
        geometryValueChanged(previous.height, height);
      viewportRef.current = { width, height };
      viewportHeightRef.current = height;
      setViewportHeight(height);
      if (changed) markGeometryChanged();
    },
    [markGeometryChanged],
  );

  const onScroll = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      scrollYRef.current = event.nativeEvent.contentOffset.y;
    },
    [],
  );

  const onCoachLayout = useCallback(
    (event: LayoutChangeEvent) => {
      const height = Math.max(0, event.nativeEvent.layout.height);
      if (!geometryValueChanged(coachHeightRef.current, height)) {
        return;
      }
      coachHeightRef.current = height;
      markGeometryChanged();
    },
    [markGeometryChanged],
  );

  const finish = useCallback(
    (type: 'SKIP' | 'FINISH') => {
      if (completedRef.current) return;
      completedRef.current = true;
      completeAppWalkthrough();
      dispatch({ type });
    },
    [completeAppWalkthrough],
  );

  const revealedGroups = useMemo(() => {
    const routeGroups = [
      ...new Set(
        APP_WALKTHROUGH_STEPS.filter((step) => step.route === route).flatMap(
          (step) => step.revealGroups,
        ),
      ),
    ];
    if (!enabled || state.phase === 'complete') return routeGroups;
    if (state.phase === 'waiting') return [];

    const revealedStepIndex =
      state.phase === 'positioning'
        ? state.stepIndex - 1
        : state.stepIndex;
    return getRevealedGroups(revealedStepIndex);
  }, [enabled, route, state.phase, state.stepIndex]);

  const active = enabled && state.phase !== 'complete';
  const locked = state.phase !== 'coaching';

  return {
    active,
    locked,
    reduceMotion: reduceMotion ?? true,
    step: currentStep,
    coachVisible: active && state.phase === 'coaching',
    coachHeadingRef,
    isRevealed: (group: AppWalkthroughRevealGroup) =>
      revealedGroups.includes(group),
    measureAnchor,
    onCoachLayout,
    onViewportLayout,
    onScroll,
    onSkip: () => finish('SKIP'),
    onPrimary: () => {
      if (locked) return;
      if (currentStep.primaryAction === 'Finish') {
        finish('FINISH');
        return;
      }

      const nextStep = APP_WALKTHROUGH_STEPS[state.stepIndex + 1];
      advanceAppWalkthrough();
      dispatch({ type: 'NEXT' });
      if (nextStep.route !== route) navigate(nextStep.route);
    },
  };
}
