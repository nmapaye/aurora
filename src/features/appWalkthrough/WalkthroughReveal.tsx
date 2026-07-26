import React, { useEffect } from 'react';
import type { StyleProp, ViewStyle } from 'react-native';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import { getRevealMotionPlan } from './motion';

type Props = {
  active: boolean;
  revealed: boolean;
  reduceMotion: boolean;
  staggerIndex?: number;
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
  testID?: string;
};

export default function WalkthroughReveal({
  active,
  revealed,
  reduceMotion,
  staggerIndex = 0,
  children,
  style,
  testID,
}: Props) {
  const progress = useSharedValue(active ? 0 : 1);
  const plan = getRevealMotionPlan(reduceMotion, staggerIndex);

  useEffect(() => {
    if (!active) {
      progress.value = 1;
      return;
    }

    if (revealed) {
      const animation =
        plan.mode === 'timing'
          ? withTiming(1, { duration: plan.durationMs })
          : withSpring(1, {
              damping: 22,
              stiffness: 220,
              mass: 0.65,
              overshootClamping: true,
            });
      progress.value = withDelay(plan.delayMs, animation);
      return;
    }

    progress.value = 0;
  }, [
    active,
    plan.delayMs,
    plan.durationMs,
    plan.mode,
    progress,
    revealed,
  ]);

  const animatedStyle = useAnimatedStyle(() => ({
    opacity: progress.value,
    transform: [
      {
        translateY: plan.initialTranslateY * (1 - progress.value),
      },
      {
        scale:
          plan.initialScale +
          (1 - plan.initialScale) * progress.value,
      },
    ],
  }));

  const hidden = active && !revealed;

  return (
    <Animated.View
      testID={testID}
      accessibilityElementsHidden={hidden}
      importantForAccessibility={
        hidden ? 'no-hide-descendants' : 'auto'
      }
      pointerEvents={hidden ? 'none' : 'auto'}
      style={[style, animatedStyle]}
    >
      {children}
    </Animated.View>
  );
}
