import React from 'react';
import { ActivityIndicator, Text, View } from 'react-native';

import Button from '~/components/Button';
import { HealthMetricCard, HealthSectionHeader, InlineStatus, SectionCard } from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
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
  const scheme = useAppScheme();
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
      <HealthSectionHeader title="Permissions" />

      <HealthMetricCard
        icon={isManual ? 'create-outline' : 'heart'}
        label={isManual ? 'Manual Mode' : 'Health'}
        labelColor={isManual ? palette.tint : '#FF2D55'}
        dateLabel={stateLabel}
        value={isManual ? 'Ready' : stateLabel}
        detail={
          isManual
            ? 'Log caffeine without Health access.'
            : 'Aurora reads sleep only.'
        }
      />

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
