import React from 'react';
import { Text, View } from 'react-native';

import Button from '~/components/Button';
import { InlineStatus, ProgressState, SectionCard } from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
import type {
  HealthImportStatus,
  HealthPermissionStatus,
  OnboardingSource,
} from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { spacing, typeRamp } from '~/theme/tokens';

type Props = {
  source: OnboardingSource;
  permissionStatus: HealthPermissionStatus;
  importStatus: HealthImportStatus;
  importMessage?: string;
  importedCount?: number;
  busy?: boolean;
  onRequest: () => void;
};

export default function StepPermissions({
  source,
  permissionStatus,
  importStatus,
  importMessage,
  importedCount = 0,
  busy = false,
  onRequest,
}: Props) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const isManual = source === 'manual';
  const healthRequestCompleted = permissionStatus === 'granted';
  const stateLabel = healthRequestCompleted && importStatus === 'failed'
    ? 'Import failed'
    : healthRequestCompleted && importStatus === 'importing'
      ? 'Importing'
      : healthRequestCompleted && importStatus === 'succeeded'
        ? importedCount > 0 ? 'Import completed' : 'No readable sleep data'
        : healthRequestCompleted
          ? 'Import pending'
          : permissionStatus === 'denied'
            ? 'Request incomplete'
            : permissionStatus === 'unsupported'
              ? 'Unavailable'
              : 'Pending';

  const statusTone = healthRequestCompleted && importStatus === 'failed'
    ? 'error'
    : healthRequestCompleted && importStatus === 'importing'
      ? 'info'
      : healthRequestCompleted && importStatus === 'succeeded'
        ? importedCount > 0 ? 'success' : 'neutral'
        : healthRequestCompleted
          ? 'warning'
          : permissionStatus === 'denied'
            ? 'error'
            : permissionStatus === 'unsupported'
              ? 'neutral'
              : 'warning';
  const importFailed = healthRequestCompleted && importStatus === 'failed';
  const failedDetail =
    importMessage?.replace(/^Health import failed\.\s*/i, '') ??
    'Unable to read sleep data.';
  const adjacentCopy = isManual
    ? 'You can connect Health later from Sleep.'
    : permissionStatus === 'denied'
      ? 'Health access request did not complete. Manual sleep logging remains available.'
      : permissionStatus === 'unsupported'
        ? 'Health import is unavailable on this device.'
        : healthRequestCompleted && importStatus === 'importing'
          ? 'Health request completed. Importing recent sleep from Health.'
          : healthRequestCompleted && importStatus === 'succeeded'
            ? importMessage ?? 'Health sleep import completed.'
            : healthRequestCompleted
              ? 'Health request completed. Recent sleep import is pending.'
              : 'Aurora reads sleep only. It does not write anything back into the Health app.';

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
        {importFailed ? (
          <Text
            accessibilityRole="alert"
            accessibilityLabel={`Health request completed. Import failed. ${failedDetail}`}
            style={{
              ...typeRamp.subheadline,
              color: palette.destructive,
            }}
          >
            Health request completed. Import failed. {failedDetail}
          </Text>
        ) : (
          <Text
            style={{
              ...typeRamp.subheadline,
              color: palette.textSecondary,
            }}
          >
            {adjacentCopy}
          </Text>
        )}
      </SectionCard>

      {!isManual ? (
        busy ? (
          <SectionCard>
            <ProgressState
              label={
                importStatus === 'importing'
                  ? 'Importing recent sleep from Health…'
                  : 'Requesting Health access…'
              }
            />
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
