import { Dimensions, Platform, useWindowDimensions } from 'react-native';
import { layout, spacing } from '~/theme/tokens';

export type AdaptiveLayout = {
  width: number;
  height: number;
  isPad: boolean;
  isWideLayout: boolean;
  isIpadWindowed: boolean;
  contentMaxWidth: number;
  topChromeBuffer: number;
  horizontalPadding: number;
  leftColumnWidth: number;
  rightColumnWidth: number;
};

export default function useAdaptiveLayout(): AdaptiveLayout {
  const { width, height } = useWindowDimensions();
  const isPad = Platform.OS === 'ios' && Platform.isPad === true;
  const screen = Dimensions.get('screen');
  const isWideLayout = isPad && width >= 900 && width > height;
  const isIpadWindowed =
    isPad && (width < screen.width - 24 || height < screen.height - 24);
  const contentMaxWidth = isWideLayout
    ? layout.wideContentMaxWidth
    : layout.contentMaxWidth;
  const horizontalPadding = isWideLayout
    ? layout.wideScreenGutter
    : layout.screenGutter;
  const topChromeBuffer = isIpadWindowed ? spacing.xl : 0;
  const availableWidth = Math.min(
    contentMaxWidth,
    Math.max(0, width - horizontalPadding * 2),
  );
  const gap = spacing.xl;
  const leftColumnWidth = isWideLayout
    ? Math.min(620, Math.max(500, availableWidth * 0.52))
    : availableWidth;
  const rightColumnWidth = isWideLayout
    ? Math.max(360, availableWidth - leftColumnWidth - gap)
    : availableWidth;

  return {
    width,
    height,
    isPad,
    isWideLayout,
    isIpadWindowed,
    contentMaxWidth,
    topChromeBuffer,
    horizontalPadding,
    leftColumnWidth,
    rightColumnWidth,
  };
}
