import React from 'react';
import Svg, { Circle, Path } from 'react-native-svg';

import useAppScheme from '~/hooks/useAppScheme';
import { auroraMark } from '~/theme/brand';
import { getAppPalette } from '~/theme/colors';

// The Aurora wave mark drawn without a tile, for in-app brand moments.
export default function BrandMark({
  size = 48,
  waveColor,
  dotColor,
  accessibilityLabel,
}: {
  size?: number;
  waveColor?: string;
  dotColor?: string;
  accessibilityLabel?: string;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const { viewBox, wavePath, waveStrokeWidth, dot, opticalCenter } =
    auroraMark;
  // Center the viewBox on the glyph, as the icon and launch image do.
  const originX = opticalCenter.x - viewBox / 2;
  const originY = opticalCenter.y - viewBox / 2;
  return (
    <Svg
      width={size}
      height={size}
      viewBox={`${originX} ${originY} ${viewBox} ${viewBox}`}
      accessible={Boolean(accessibilityLabel)}
      accessibilityLabel={accessibilityLabel}
      accessibilityRole={accessibilityLabel ? 'image' : undefined}
    >
      <Path
        d={wavePath}
        stroke={waveColor ?? palette.tint}
        strokeWidth={waveStrokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
      <Circle
        cx={dot.cx}
        cy={dot.cy}
        r={dot.r}
        fill={dotColor ?? palette.textPrimary}
      />
    </Svg>
  );
}
