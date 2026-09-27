import * as Haptics from 'expo-haptics';

// Haptics are feedback, not motion, so they ignore Reduce Motion. iOS already
// silences them when the user turns off System Haptics. Failures (simulator,
// unsupported hardware) are never surfaced.
function fire(effect: () => Promise<void>) {
  try {
    void effect().catch(() => undefined);
  } catch {
    // expo-haptics unavailable in this runtime
  }
}

export const haptics = {
  /** A value moved: segmented controls, steppers, chart scrubbing. */
  selection: () => fire(() => Haptics.selectionAsync()),
  /** A light physical tap: quick add, reaction-test responses. */
  tap: () => fire(() => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light)),
  /** Something was saved. */
  success: () =>
    fire(() => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)),
  /** A mistake or a destructive action: false starts, deletions. */
  warning: () =>
    fire(() => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning)),
};
