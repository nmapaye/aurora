import React from 'react';
import { Text, View } from 'react-native';

import AppIcon, { type AppIconName } from '~/components/AppIcon';
import Button from '~/components/Button';
import {
  Divider,
  InlineStatus,
  ProgressState,
  SectionCard,
} from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
import type {
  HealthImportStatus,
  HealthPermissionStatus,
  OnboardingSource,
} from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, iconSizes, spacing, typeRamp } from '~/theme/tokens';

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
        ? importedCount > 0 ? 'Import completed' : 'No sleep found'
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
      ? 'Health access wasn’t set up. You can still log sleep manually.'
      : permissionStatus === 'unsupported'
        ? 'Health import is unavailable on this device.'
        : healthRequestCompleted && importStatus === 'importing'
          ? 'Health access requested. Importing recent sleep from Health.'
          : healthRequestCompleted && importStatus === 'succeeded'
            ? importMessage ?? 'Health sleep import completed.'
            : healthRequestCompleted
              ? 'Health access requested. Your sleep import hasn’t finished.'
              : 'Aurora reads sleep only. It does not write anything back into the Health app.';

  // Before any request, explain what will be asked instead of showing a
  // status for something that has not happened yet.
  const showFacts = !isManual && permissionStatus === 'idle';

  return (
    <View style={{ gap: spacing.md }}>
      {isManual ? (
        <SectionCard>
          <FactRow
            icon="create-outline"
            title="Log as you go"
            body="Add caffeine from Log and nights from Sleep. Aurora reads nothing from Health."
          />
        </SectionCard>
      ) : showFacts ? (
        <SectionCard style={{ gap: spacing.md }}>
          <FactRow
            icon="moon-outline"
            title="Sleep only"
            body="Aurora requests read access to sleep analysis and nothing else."
          />
          <Divider inset={iconSizes.button + spacing.sm} />
          <FactRow
            icon="lock-closed-outline"
            title="Read-only"
            body="Aurora reads sleep only. It does not write anything back into the Health app."
          />
          <Divider inset={iconSizes.button + spacing.sm} />
          <FactRow
            icon="options-outline"
            title="Your choice"
            body="Pick what to share in the Health sheet, and change it anytime in the Health app."
          />
        </SectionCard>
      ) : (
        <SectionCard>
          <InlineStatus tone={statusTone} text={`Status: ${stateLabel}`} />
          {importFailed ? (
            <Text
              accessibilityRole="alert"
              accessibilityLabel={`Health access requested, but the import failed. ${failedDetail}`}
              maxFontSizeMultiplier={fontScaling.body}
              style={{
                ...typeRamp.subheadline,
                color: palette.destructive,
              }}
            >
              Health access requested, but the import failed. {failedDetail}
            </Text>
          ) : (
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{
                ...typeRamp.subheadline,
                color: palette.textSecondary,
              }}
            >
              {adjacentCopy}
            </Text>
          )}
        </SectionCard>
      )}

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
          // After a request, Finish setup becomes the primary action and this
          // stays available as a quieter retry.
          <Button
            title="Allow Health Access"
            variant={showFacts ? 'primary' : 'tinted'}
            onPress={onRequest}
          />
        )
      ) : null}
    </View>
  );
}

function FactRow({
  icon,
  title,
  body,
}: {
  icon: AppIconName;
  title: string;
  body: string;
}) {
  const palette = getAppPalette(useAppScheme());
  return (
    <View
      accessible
      style={{ flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm }}
    >
      <AppIcon name={icon} size={iconSizes.button} color={palette.tint} />
      <View style={{ flex: 1, gap: spacing.xxs }}>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.headline, color: palette.textPrimary }}
        >
          {title}
        </Text>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.subheadline, color: palette.textSecondary }}
        >
          {body}
        </Text>
      </View>
    </View>
  );
}
