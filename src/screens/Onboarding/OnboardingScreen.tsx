import React, { useMemo, useState } from 'react';
import { Text, View } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { InlineStatus, ListRow, SectionCard } from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
import StepPermissions from '~/screens/Onboarding/steps/StepPermissions';
import StepSleepTarget from '~/screens/Onboarding/steps/StepSleepTarget';
import StepSources from '~/screens/Onboarding/steps/StepSources';
import AppleHealth, { makeHealthSleepSessionId } from '~/services/platform/health/appleHealth';
import { requestHealthPermissions } from '~/services/permissions';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { radii, spacing, typeRamp } from '~/theme/tokens';

const TOTAL_STEPS = 3;

export default function OnboardingScreen() {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const targetSleep = useStore((state) => state.prefs.targetSleep);
  const setPrefs = useStore((state) => state.setPrefs);
  const onboarding = useStore((state) => state.onboarding);
  const healthSync = useStore((state) => state.healthSync);
  const setOnboarding = useStore((state) => state.setOnboarding);
  const completeOnboarding = useStore((state) => state.completeOnboarding);
  const upsertSleepSessions = useStore((state) => state.upsertSleepSessions);
  const setHealthSync = useStore((state) => state.setHealthSync);
  const loadDemoData = useStore((state) => state.loadDemoData);

  const [step, setStep] = useState(0);
  const [requestingPermission, setRequestingPermission] = useState(false);

  const canAdvance = useMemo(() => {
    if (step < TOTAL_STEPS - 1) return true;
    if (onboarding.source === 'manual') return true;
    return onboarding.permissionStatus !== 'idle';
  }, [onboarding.permissionStatus, onboarding.source, step]);

  const handleRequestPermission = async () => {
    setRequestingPermission(true);
    try {
      const result = await requestHealthPermissions();
      setOnboarding({
        source: onboarding.source,
        permissionStatus: result.status,
      });

      if (result.status === 'granted') {
        setHealthSync({
          importStatus: 'importing',
          lastMessage: 'Importing recent sleep from Health.',
        });
        const end = Date.now();
        const start = end - 14 * 24 * 60 * 60 * 1000;
        try {
          const samples = await AppleHealth.getSleepSamples(start, end);
          if (!Array.isArray(samples)) {
            throw new Error('Health sleep query returned an invalid payload.');
          }
          upsertSleepSessions(
            samples.map((sample) => ({
              id: makeHealthSleepSessionId(sample),
              start: sample.start,
              end: sample.end,
              type: 'sleep' as const,
            })),
          );
          setHealthSync({
            importedCount: samples.length,
            importStatus: 'succeeded',
            lastSyncedAt: Date.now(),
            lastMessage:
              samples.length > 0
                ? `Imported ${samples.length} recent sleep sample${samples.length === 1 ? '' : 's'} from Health.`
                : 'No recent readable sleep samples were found. There may be no records, or read access may be off. Manual sleep logging remains available.',
          });
        } catch (error) {
          const message =
            error instanceof Error
              ? error.message
              : 'Unable to read sleep data.';
          const importMessage = `Health import failed. ${message}`;
          setHealthSync({
            importStatus: 'failed',
            lastSyncedAt: Date.now(),
            lastMessage: importMessage,
          });
        }
      } else {
        setHealthSync({
          importStatus: 'idle',
          lastMessage: result.message,
        });
      }
    } finally {
      setRequestingPermission(false);
    }
  };

  const next = () => {
    if (step < TOTAL_STEPS - 1) {
      setStep((current) => current + 1);
      return;
    }
    completeOnboarding();
  };

  const startDemo = () => {
    loadDemoData();
  };

  const back = () => setStep((current) => Math.max(0, current - 1));
  const nextAction =
    onboarding.source === 'manual'
      ? 'Finish setup to log caffeine manually. You can also try Aurora with sample data.'
      : onboarding.permissionStatus === 'granted' &&
          healthSync.importStatus === 'succeeded'
        ? healthSync.importedCount > 0
          ? 'Finish setup, then review imported sleep.'
          : 'Finish setup to log sleep manually, or check sleep records and access in Health.'
        : onboarding.permissionStatus === 'granted' &&
            healthSync.importStatus === 'importing'
          ? 'Health request completed. Sleep import is in progress.'
          : onboarding.permissionStatus === 'granted' &&
              healthSync.importStatus === 'failed'
            ? 'Health request completed. Sleep import needs a retry.'
            : onboarding.permissionStatus === 'granted'
              ? 'Health request completed. Recent sleep has not been imported yet.'
        : 'Connect Health, or finish with manual setup.';

  return (
    <AppScreen
      title="Set Up"
      subtitle={`Step ${step + 1} of ${TOTAL_STEPS}`}
      trailing={<View style={{ width: 36, height: 36 }} />}
      topInset={24}
    >
      <View style={{ gap: spacing.lg }}>
        <View style={{ gap: spacing.sm }}>
          <Text
            style={{
              ...typeRamp.footnote,
              fontWeight: '600',
              color: palette.textSecondary,
            }}
          >
            Aurora
          </Text>
          <View style={{ flexDirection: 'row', gap: spacing.xs }}>
            {Array.from({ length: TOTAL_STEPS }).map((_, index) => (
              <View
                key={index}
                style={{
                  flex: 1,
                  height: 6,
                  borderRadius: radii.capsule,
                  backgroundColor:
                    index <= step ? palette.tint : palette.cardMuted,
                }}
              />
            ))}
          </View>
        </View>

        {step === 0 ? (
          <StepSleepTarget
            targetSleep={targetSleep}
            onChange={(value) => setPrefs({ targetSleep: value })}
          />
        ) : null}

        {step === 1 ? (
          <StepSources
            selectedSource={onboarding.source}
            onSelect={(value) =>
              setOnboarding({
                source: value,
                permissionStatus: value === 'manual' ? 'unsupported' : 'idle',
              })
            }
          />
        ) : null}

        {step === 2 ? (
          <StepPermissions
            source={onboarding.source}
            permissionStatus={onboarding.permissionStatus}
            importStatus={healthSync.importStatus}
            importedCount={healthSync.importedCount}
            importMessage={healthSync.lastMessage}
            busy={requestingPermission}
            onRequest={handleRequestPermission}
          />
        ) : null}

        {step === 2 ? (
          <SectionCard>
            <InlineStatus tone="info" text="Sample Data" />
            <ListRow title="Try Aurora with examples" subtitle={nextAction} />
            <Button
              title="Load Sample Data"
              variant="tinted"
              onPress={startDemo}
              disabled={requestingPermission}
            />
          </SectionCard>
        ) : null}

        <View style={{ flexDirection: 'row', gap: spacing.sm }}>
          {step > 0 ? (
            <Button title="Back" variant="tinted" onPress={back} />
          ) : (
            <View style={{ width: 88 }} />
          )}
          <View style={{ flex: 1 }} />
          <Button
            title={step === TOTAL_STEPS - 1 ? 'Finish setup' : 'Continue'}
            onPress={next}
            disabled={!canAdvance}
          />
        </View>
      </View>
    </AppScreen>
  );
}
