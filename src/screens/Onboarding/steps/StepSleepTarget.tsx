import React from 'react';
import { Pressable, Text, View, PlatformColor } from 'react-native';

type Props = {
  targetSleep: number;
  onChange: (value: number) => void;
};

export default function StepSleepTarget({ targetSleep, onChange }: Props) {
  const presets = [7, 8, 9];

  return (
    <View style={{ gap: 16 }}>
      <View style={{ gap: 8 }}>
        <Text style={{ fontSize: 28, lineHeight: 34, fontWeight: '700', color: PlatformColor('label') }}>
          Sleep target
        </Text>
        <Text style={{ fontSize: 16, lineHeight: 22, color: PlatformColor('secondaryLabel') }}>
          Set the amount of sleep Aurora should protect when it recommends your caffeine cutoff.
        </Text>
      </View>

      <View
        style={{
          padding: 20,
          borderRadius: 20,
          backgroundColor: PlatformColor('secondarySystemBackground'),
          borderWidth: 1,
          borderColor: PlatformColor('separator'),
        }}
      >
        <Text style={{ fontSize: 44, lineHeight: 50, fontWeight: '700', color: PlatformColor('label') }}>
          {targetSleep.toFixed(1)}h
        </Text>
        <Text style={{ marginTop: 6, fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
          You can fine-tune this later in Settings.
        </Text>
      </View>

      <View style={{ flexDirection: 'row', gap: 12 }}>
        <Pressable
          onPress={() => onChange(Math.max(5, Math.round((targetSleep - 0.5) * 2) / 2))}
          accessibilityRole="button"
          style={{
            minWidth: 56,
            minHeight: 56,
            alignItems: 'center',
            justifyContent: 'center',
            borderRadius: 16,
            backgroundColor: PlatformColor('tertiarySystemBackground'),
          }}
        >
          <Text style={{ fontSize: 24, color: PlatformColor('label') }}>−</Text>
        </Pressable>
        <Pressable
          onPress={() => onChange(Math.min(10, Math.round((targetSleep + 0.5) * 2) / 2))}
          accessibilityRole="button"
          style={{
            minWidth: 56,
            minHeight: 56,
            alignItems: 'center',
            justifyContent: 'center',
            borderRadius: 16,
            backgroundColor: PlatformColor('tertiarySystemBackground'),
          }}
        >
          <Text style={{ fontSize: 24, color: PlatformColor('label') }}>+</Text>
        </Pressable>
      </View>

      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 12 }}>
        {presets.map((preset) => {
          const selected = preset === Math.round(targetSleep);
          return (
            <Pressable
              key={preset}
              onPress={() => onChange(preset)}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              style={{
                minHeight: 44,
                paddingHorizontal: 16,
                paddingVertical: 10,
                borderRadius: 999,
                backgroundColor: selected ? PlatformColor('systemFill') : PlatformColor('tertiarySystemBackground'),
                borderWidth: 1,
                borderColor: PlatformColor('separator'),
              }}
            >
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('label') }}>{preset} hours</Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}
