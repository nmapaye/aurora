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

import { spacing } from '~/theme/tokens';
import {
  getRevealedGroups,
  getTargetScrollY,
  initialWalkthroughState,
  isTargetFullyVisible,
  reduceWalkthrough,
  SUMMARY_WALKTHROUGH_STEPS,
  WALKTHROUGH_REDUCED_MOTION_SETTLE_MS,
  WALKTHROUGH_REVEAL_SETTLE_MS,
  WALKTHROUGH_SCROLL_SETTLE_MS,
  WALKTHROUGH_START_DELAY_MS,
  WALKTHROUGH_TOP_CLEARANCE,
} from './model';
import type {
  SummaryAnchorId,
  SummaryRevealGroup,
} from './model';

type AnchorMeasurement = { y: number; height: number };

const WALKTHROUGH_COACH_FALLBACK_CLEARANCE = 180;

type Options = {
  enabled: boolean;
  hasAlert: boolean;
  isWideLayout: boolean;
  scrollRef: RefObject<ScrollView | null>;
  contentRef: RefObject<View | null>;
  onComplete: () => void;
};

export default function useSummaryWalkthrough({
  enabled,
  hasAlert,
  isWideLayout,
  scrollRef,
  contentRef,
  onComplete,
}: Options) {
  const [state, dispatch] = useReducer(
    reduceWalkthrough,
    initialWalkthroughState,
  );
  const [reduceMotion, setReduceMotion] = useState<boolean | null>(null);
  const [viewportHeight, setViewportHeight] = useState(0);
  const viewportHeightRef = useRef(0);
  const scrollYRef = useRef(0);
  const anchorsRef = useRef<
    Partial<Record<SummaryAnchorId, AnchorMeasurement>>
  >({ top: { y: 0, height: 1 } });
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
  const announcedStagesRef = useRef(new Set<number>());

  scrollViewRef.current = scrollRef;

  useEffect(() => {
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
  }, []);

  useEffect(() => {
    if (
      !enabled ||
      reduceMotion === null ||
      viewportHeight <= 0 ||
      state.phase !== 'waiting'
    ) {
      return;
    }

    startTimerRef.current = setTimeout(() => {
      dispatch({ type: 'START' });
    }, WALKTHROUGH_START_DELAY_MS);

    return () => {
      if (startTimerRef.current) clearTimeout(startTimerRef.current);
    };
  }, [enabled, reduceMotion, state.phase, viewportHeight]);

  useEffect(() => {
    const stageIndex = state.stageIndex;
    if (
      !enabled ||
      state.phase !== 'positioning' ||
      reduceMotion === null
    ) {
      return;
    }

    const currentStep = SUMMARY_WALKTHROUGH_STEPS[stageIndex];
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
      if (!visible) {
        shouldAnimateScroll = !reduceMotion;
        scrollViewRef.current.current?.scrollTo({
          y: getTargetScrollY(
            target.y,
            WALKTHROUGH_TOP_CLEARANCE,
          ),
          animated: !reduceMotion,
        });
      }
    }

    settleTimerRef.current = setTimeout(
      () => dispatch({ type: 'POSITIONED' }),
      shouldAnimateScroll ? WALKTHROUGH_SCROLL_SETTLE_MS : 0,
    );

    return () => {
      if (settleTimerRef.current) clearTimeout(settleTimerRef.current);
    };
  }, [enabled, reduceMotion, state.phase, state.stageIndex]);

  const currentStep = SUMMARY_WALKTHROUGH_STEPS[state.stageIndex];

  useEffect(() => {
    if (!enabled || state.phase !== 'revealing' || reduceMotion === null) {
      return;
    }

    settleTimerRef.current = setTimeout(
      () => dispatch({ type: 'SETTLED' }),
      reduceMotion
        ? WALKTHROUGH_REDUCED_MOTION_SETTLE_MS
        : WALKTHROUGH_REVEAL_SETTLE_MS,
    );

    return () => {
      if (settleTimerRef.current) clearTimeout(settleTimerRef.current);
    };
  }, [enabled, reduceMotion, state.phase]);

  useEffect(() => {
    if (
      state.phase !== 'coaching' ||
      announcedStagesRef.current.has(state.stageIndex)
    ) {
      return;
    }
    announcedStagesRef.current.add(state.stageIndex);

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
    reduceMotion,
    state.phase,
    state.stageIndex,
  ]);

  useEffect(
    () => () => {
      if (settleTimerRef.current) clearTimeout(settleTimerRef.current);
      if (startTimerRef.current) clearTimeout(startTimerRef.current);
    },
    [],
  );

  const measureAnchor = useCallback(
    (id: SummaryAnchorId, node: View | null) => {
      if (!node || !contentRef.current) return;
      node.measureLayout(
        contentRef.current,
        (_x, y, _width, height) => {
          anchorsRef.current = {
            ...anchorsRef.current,
            [id]: { y, height },
          };
        },
        () => {},
      );
    },
    [contentRef],
  );

  const onViewportLayout = useCallback((event: LayoutChangeEvent) => {
    const height = event.nativeEvent.layout.height;
    viewportHeightRef.current = height;
    setViewportHeight(height);
  }, []);

  const onScroll = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      scrollYRef.current = event.nativeEvent.contentOffset.y;
    },
    [],
  );

  const onCoachLayout = useCallback((event: LayoutChangeEvent) => {
    coachHeightRef.current = Math.max(
      0,
      event.nativeEvent.layout.height,
    );
  }, []);

  const finish = useCallback(
    (type: 'SKIP' | 'FINISH') => {
      if (completedRef.current) return;
      completedRef.current = true;
      onComplete();
      dispatch({ type });
    },
    [onComplete],
  );

  const revealedGroups = useMemo(() => {
    const allGroups: SummaryRevealGroup[] = [
      'header',
      'alert',
      'pinned',
      'today',
      'logging',
      'recent',
    ];
    if (!enabled || state.phase === 'complete') return allGroups;
    if (state.phase === 'waiting') return [];

    const revealedStageIndex =
      state.phase === 'positioning'
        ? state.stageIndex - 1
        : state.stageIndex;
    return getRevealedGroups(revealedStageIndex, {
      hasAlert,
      isWideLayout,
    });
  }, [enabled, hasAlert, isWideLayout, state.phase, state.stageIndex]);

  const active = enabled && state.phase !== 'complete';
  const locked = state.phase !== 'coaching';

  return {
    active,
    locked,
    reduceMotion: reduceMotion ?? true,
    step: currentStep,
    coachVisible: active && state.phase === 'coaching',
    coachHeadingRef,
    isRevealed: (group: SummaryRevealGroup) =>
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
      } else {
        dispatch({ type: 'NEXT' });
      }
    },
  };
}
