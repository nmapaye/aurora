import React, { useMemo, useState } from 'react';
import { Text, View, useColorScheme } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { InlineStatus, ListRow, SectionCard } from '~/components/ui';
import StepPermissions from '~/screens/Onboarding/steps/StepPermissions';
import StepSleepTarget from '~/screens/Onboarding/steps/StepSleepTarget';
import StepSources from '~/screens/Onboarding/steps/StepSources';
import AppleHealth from '~/services/platform/health/appleHealth';
import { requestHealthPermissions } from '~/services/permissions';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';

const TOTAL_STEPS = 3;

function toSleepSessionId(start: number, end: number) {
  return `sleep:${start}:${end}`;
}

export default function OnboardingScreen() {
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const targetSleep = useStore((state) => state.prefs.targetSleep);
  const setPrefs = useStore((state) => state.setPrefs);
  const onboarding = useStore((state) => state.onboarding);
  const setOnboarding = useStore((state) => state.setOnboarding);
  const completeOnboarding = useStore((state) => state.completeOnboarding);
  const upsertSleepSessions = useStore((state) => state.upsertSleepSessions);
  const setHealthSync = useStore((state) => state.setHealthSync);
  const loadDemoData = useStore((state) => state.loadDemoData);

  const [step, setStep] = useState(0);
  const [permissionMessage, setPermissionMessage] = useState<string>();
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
      setPermissionMessage(result.message);

      if (result.status === 'granted') {
        const end = Date.now();
        const start = end - 14 * 24 * 60 * 60 * 1000;
        const samples = await AppleHealth.getSleepSamples(start, end);
        upsertSleepSessions(
          samples.map((sample) => ({
            id: toSleepSessionId(sample.start, sample.end),
            start: sample.start,
            end: sample.end,
            type: 'sleep' as const,
          }))
        );
        setHealthSync({
          importedCount: samples.length,
          lastSyncedAt: Date.now(),
          lastMessage:
            samples.length > 0
              ? `Imported ${samples.length} recent sleep sample${samples.length === 1 ? '' : 's'} from Health.`
              : 'Health connected, but no recent sleep samples were found.',
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
      ? 'Finish setup to log caffeine manually. Use the reviewer shortcut only when you want a fully seeded walkthrough.'
      : onboarding.permissionStatus === 'granted'
      ? 'Finish setup, then review imported sleep and log your next caffeine intake.'
      : 'Connect Health for sleep samples, or switch to manual setup and finish without permissions.';

  return (
    <AppScreen
      title="Set up Aurora"
      subtitle={`Step ${step + 1} of ${TOTAL_STEPS}`}
      trailing={<View style={{ width: 36, height: 36 }} />}
      topInset={24}
    >
      <View style={{ gap: 20 }}>
        <View style={{ gap: 10 }}>
          <Text
            style={{
              fontSize: 13,
              lineHeight: 18,
              fontWeight: '600',
              color: palette.textSecondary,
              textTransform: 'uppercase',
            }}
          >
            iPhone-first setup
          </Text>
          <View style={{ flexDirection: 'row', gap: 8 }}>
            {Array.from({ length: TOTAL_STEPS }).map((_, index) => (
              <View
                key={index}
                style={{
                  flex: 1,
                  height: 6,
                  borderRadius: 999,
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
            message={permissionMessage}
            busy={requestingPermission}
            onRequest={handleRequestPermission}
          />
        ) : null}

        {step === 2 ? (
          <SectionCard>
            <InlineStatus tone="info" text="Reviewer shortcut" />
            <ListRow
              title="Use sample data for a complete review"
              subtitle={nextAction}
            />
            <Button
              title="Load reviewer sample"
              variant="secondary"
              onPress={startDemo}
              disabled={requestingPermission}
            />
          </SectionCard>
        ) : null}

        <View style={{ flexDirection: 'row', gap: 12 }}>
          {step > 0 ? (
            <Button title="Back" variant="secondary" onPress={back} />
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
