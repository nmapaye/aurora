import React from 'react';
import { Text, View } from 'react-native';

import Button from '~/components/Button';
import { InlineStatus, ProgressState, SectionCard } from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
import type { HealthPermissionStatus, OnboardingSource } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { spacing, typeRamp } from '~/theme/tokens';

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
    <View style={{ gap: spacing.md }}>
      <View style={{ gap: spacing.xs }}>
        <Text
          style={{
            ...typeRamp.title1,
            fontWeight: '700',
            letterSpacing: 0,
            color: palette.textPrimary,
          }}
        >
          Permissions
        </Text>
        <Text
          style={{
            ...typeRamp.body,
            color: palette.textSecondary,
          }}
        >
          {isManual
            ? 'Manual mode is ready.'
            : 'Allow Aurora to read recent sleep from Health.'}
        </Text>
      </View>

      <SectionCard>
        <InlineStatus tone={statusTone} text={`Status: ${stateLabel}`} />
        <Text
          style={{
            ...typeRamp.subheadline,
            color: palette.textSecondary,
          }}
        >
          {message ??
            (isManual
              ? 'You can connect Health later from Sleep.'
              : 'Aurora reads sleep only. It does not write anything back into the Health app.')}
        </Text>
      </SectionCard>

      {!isManual ? (
        busy ? (
          <SectionCard>
            <ProgressState label="Requesting Health access…" />
          </SectionCard>
        ) : (
          <Button
            title="Allow Health Access"
            variant="primary"
            onPress={onRequest}
          />
        )
      ) : null}
    </View>
  );
}
