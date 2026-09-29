import React from 'react';
import { View } from 'react-native';
import Svg, { Circle, G, Path } from 'react-native-svg';

import useAppScheme from '~/hooks/useAppScheme';
import { auroraHorizon } from '~/theme/brand';
import { getAppPalette } from '~/theme/colors';

// Decorative horizon drawn from the wave mark. Hidden from assistive tech.
export default function BrandHorizon({ maxWidth }: { maxWidth?: number }) {
  const palette = getAppPalette(useAppScheme());
  const { width, height, wavePath, ribbonOffset, ribbonOpacities, strokeWidth, dot } =
    auroraHorizon;
  return (
    <View
      testID="brand-horizon"
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
      pointerEvents="none"
      style={{ width: '100%', maxWidth, aspectRatio: width / height }}
    >
      <Svg width="100%" height="100%" viewBox={`0 0 ${width} ${height}`}>
        {ribbonOpacities.map((opacity, index) => (
          <G key={index} transform={`translate(0 ${index * ribbonOffset})`}>
            <Path
              d={wavePath}
              stroke={palette.tint}
              strokeOpacity={opacity}
              strokeWidth={strokeWidth}
              strokeLinecap="round"
              strokeLinejoin="round"
              fill="none"
            />
          </G>
        ))}
        <Circle cx={dot.cx} cy={dot.cy} r={dot.r} fill={palette.textPrimary} />
      </Svg>
    </View>
  );
}
