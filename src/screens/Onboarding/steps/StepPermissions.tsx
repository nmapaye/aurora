import React from 'react';
import { ActivityIndicator, Pressable, Text, View, PlatformColor } from 'react-native';

import type { HealthPermissionStatus, OnboardingSource } from '~/state/store';

type Props = {
  source: OnboardingSource;
  permissionStatus: HealthPermissionStatus;
  message?: string;
  busy?: boolean;
  onRequest: () => void;
};

export default function StepPermissions({
  source,
  permissionStatus,
  message,
  busy = false,
  onRequest,
}: Props) {
  const isManual = source === 'manual';
  const stateLabel =
    permissionStatus === 'granted'
      ? 'Connected'
      : permissionStatus === 'denied'
        ? 'Not granted'
        : permissionStatus === 'unsupported'
          ? 'Unavailable'
          : 'Pending';

  return (
    <View style={{ gap: 16 }}>
      <View style={{ gap: 8 }}>
        <Text style={{ fontSize: 28, lineHeight: 34, fontWeight: '700', color: PlatformColor('label') }}>
          Permissions
        </Text>
        <Text style={{ fontSize: 16, lineHeight: 22, color: PlatformColor('secondaryLabel') }}>
          {isManual
            ? 'Manual mode is ready. You can finish setup now and start logging doses immediately.'
            : 'Grant Health access so Aurora can import recent sleep and tailor your guidance.'}
        </Text>
      </View>

      <View
        style={{
          padding: 18,
          borderRadius: 20,
          backgroundColor: PlatformColor('secondarySystemBackground'),
          borderWidth: 1,
          borderColor: PlatformColor('separator'),
          gap: 10,
        }}
      >
        <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>
          Status: {stateLabel}
        </Text>
        <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
          {message ??
            (isManual
              ? 'Aurora will use manual caffeine logs until you connect Health.'
              : 'Aurora reads sleep only. It does not write data back into Health.' )}
        </Text>
      </View>

      {!isManual ? (
        <Pressable
          onPress={onRequest}
          accessibilityRole="button"
          disabled={busy}
          style={{
            minHeight: 52,
            borderRadius: 16,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: PlatformColor('tintColor'),
            opacity: busy ? 0.7 : 1,
          }}
        >
          {busy ? (
            <ActivityIndicator color="#FFFFFF" />
          ) : (
            <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '600', color: '#FFFFFF' }}>
              Allow Health access
            </Text>
          )}
        </Pressable>
      ) : null}
    </View>
  );
}
