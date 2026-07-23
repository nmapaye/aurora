import { spacing } from '~/theme/tokens';

export function getAppScreenBottomPadding(
  safeInset: number,
  overlayHeight: number,
) {
  const measuredOverlayHeight = Math.max(0, overlayHeight);

  return (
    spacing.xxl +
    Math.max(0, safeInset) +
    measuredOverlayHeight +
    (measuredOverlayHeight > 0 ? spacing.sm : 0)
  );
}
