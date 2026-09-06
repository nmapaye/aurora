import React from 'react';
import { Text, TextInput, View } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { getAppPalette } from '~/theme/colors';
import { typeRamp } from '~/theme/tokens';
import useAppScheme from '~/hooks/useAppScheme';
export const timeText = (value: number) =>
  new Date(value).toLocaleString([], {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
let counter = 0;
export const planningId = (kind: string) =>
  `personal:${kind}:${Date.now()}:${++counter}`;
export function PlanningText({ children }: { children: React.ReactNode }) {
  const palette = getAppPalette(useAppScheme());
  return (
    <Text style={{ ...typeRamp.body, color: palette.textPrimary }}>
      {children}
    </Text>
  );
}
export function PlanningField({
  label,
  value,
  onChange,
  disabled = false,
  numeric = false,
}: {
  label: string;
  value: string;
  onChange: (s: string) => void;
  disabled?: boolean;
  numeric?: boolean;
}) {
  const palette = getAppPalette(useAppScheme());
  return (
    <View style={{ gap: 4 }}>
      <PlanningText>{label}</PlanningText>
      <TextInput
        accessibilityLabel={label}
        value={value}
        onChangeText={onChange}
        editable={!disabled}
        keyboardType={numeric ? 'decimal-pad' : 'default'}
        style={{
          ...typeRamp.body,
          minHeight: 48,
          padding: 10,
          borderWidth: 1,
          borderColor: palette.textSecondary,
          borderRadius: 10,
          color: palette.textPrimary,
        }}
      />
    </View>
  );
}
export const validNumber = (value: string, min: number, max: number) =>
  value.trim() !== '' &&
  Number.isFinite(Number(value)) &&
  Number(value) >= min &&
  Number(value) <= max;
export function ProjectionCurve({
  points,
}: {
  points: { timestamp: number; mg: number }[];
}) {
  const palette = getAppPalette(useAppScheme()),
    max = Math.max(1, ...points.map((p) => p.mg)),
    start = points[0]?.timestamp ?? 0,
    span = Math.max(1, (points[points.length - 1]?.timestamp ?? 0) - start);
  const path = points
    .map(
      (p, i) =>
        `${i ? 'L' : 'M'} ${10 + ((p.timestamp - start) / span) * 280} ${150 - (p.mg / max) * 140}`,
    )
    .join(' ');
  return (
    <View
      accessible={false}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <Svg width="100%" height={160} viewBox="0 0 300 160">
        <Path
          d={path}
          fill="none"
          stroke={palette.textPrimary}
          strokeWidth={3}
        />
      </Svg>
    </View>
  );
}
