import React from 'react';
import { ActivityIndicator, Text, View, useColorScheme } from 'react-native';

import Button from '~/components/Button';
import { InlineStatus, SectionCard } from '~/components/ui';
import type { HealthPermissionStatus, OnboardingSource } from '~/state/store';
import { getAppPalette } from '~/theme/colors';

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
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const isManual = source === 'manual';
  const stateLabel =
    permissionStatus === 'granted'
      ? 'Connected'
      : permissionStatus === 'denied'
      ? 'Not granted'
      : permissionStatus === 'unsupported'
      ? 'Unavailable'
      : 'Pending';

  const statusTone =
    permissionStatus === 'granted'
      ? 'success'
      : permissionStatus === 'denied'
      ? 'error'
      : permissionStatus === 'unsupported'
      ? 'neutral'
      : 'warning';

  return (
    <View style={{ gap: 16 }}>
      <View style={{ gap: 8 }}>
        <Text
          style={{
            fontSize: 30,
            lineHeight: 36,
            fontWeight: '700',
            letterSpacing: -0.4,
            color: palette.textPrimary,
          }}
        >
          Permissions
        </Text>
        <Text
          style={{
            fontSize: 16,
            lineHeight: 22,
            color: palette.textSecondary,
          }}
        >
          {isManual
            ? 'Manual mode is ready. Finish setup now and start logging doses immediately.'
            : 'Grant Health access so Aurora can import recent sleep and tailor guidance to your actual recovery.'}
        </Text>
      </View>

      <SectionCard>
        <InlineStatus tone={statusTone} text={`Status: ${stateLabel}`} />
        <Text
          style={{
            fontSize: 15,
            lineHeight: 20,
            color: palette.textSecondary,
          }}
        >
          {message ??
            (isManual
              ? 'Aurora will use manual caffeine logs until you connect Health later.'
              : 'Aurora reads sleep only. It does not write anything back into the Health app.')}
        </Text>
      </SectionCard>

      {!isManual ? (
        busy ? (
          <SectionCard>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
              <ActivityIndicator color={palette.tint} />
              <Text
                style={{
                  fontSize: 15,
                  lineHeight: 20,
                  color: palette.textSecondary,
                }}
              >
                Requesting Health access…
              </Text>
            </View>
          </SectionCard>
        ) : (
          <Button title="Allow Health access" onPress={onRequest} />
        )
      ) : null}
    </View>
  );
}
