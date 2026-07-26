import { useEffect, useState } from 'react';
import { AccessibilityInfo } from 'react-native';

export default function useReduceMotion() {
  const [reduceMotion, setReduceMotion] = useState(true);

  useEffect(() => {
    let active = true;
    let receivedSystemEvent = false;
    const onReduceMotionChanged = (enabled: boolean) => {
      receivedSystemEvent = true;
      if (active) setReduceMotion(enabled);
    };

    AccessibilityInfo.isReduceMotionEnabled()
      .then((enabled) => {
        if (active && !receivedSystemEvent) setReduceMotion(enabled);
      })
      .catch(() => {
        if (active && !receivedSystemEvent) setReduceMotion(true);
      });
    const subscription = AccessibilityInfo.addEventListener(
      'reduceMotionChanged',
      onReduceMotionChanged,
    );
    return () => {
      active = false;
      subscription.remove();
    };
  }, []);

  return reduceMotion;
}
