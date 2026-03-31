import React, { useMemo, useState } from 'react';
import { PlatformColor, Pressable, Text, View } from 'react-native';

import Button from '~/components/Button';
import ScreenContainer from '~/components/ScreenContainer';
import StepPermissions from '~/screens/Onboarding/steps/StepPermissions';
import StepSleepTarget from '~/screens/Onboarding/steps/StepSleepTarget';
import StepSources from '~/screens/Onboarding/steps/StepSources';
import AppleHealth from '~/services/platform/health/appleHealth';
import { requestHealthPermissions } from '~/services/permissions';
import { useStore } from '~/state/store';

const TOTAL_STEPS = 3;

function toSleepSessionId(start: number, end: number) {
  return `sleep:${start}:${end}`;
}

export default function OnboardingScreen() {
  const targetSleep = useStore((s) => s.prefs.targetSleep);
  const setPrefs = useStore((s) => s.setPrefs);
  const onboarding = useStore((s) => s.onboarding);
  const setOnboarding = useStore((s) => s.setOnboarding);
  const completeOnboarding = useStore((s) => s.completeOnboarding);
  const upsertSleepSessions = useStore((s) => s.upsertSleepSessions);

  const [step, setStep] = useState(0);
  const [permissionMessage, setPermissionMessage] = useState<string>();
  const [requestingPermission, setRequestingPermission] = useState(false);

  const canAdvance = useMemo(() => {
    if (step < 2) {
      return true;
    }
    if (onboarding.source === 'manual') {
      return true;
    }
    return onboarding.permissionStatus !== 'idle';
  }, [step, onboarding.permissionStatus, onboarding.source]);

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

  const back = () => setStep((current) => Math.max(0, current - 1));

  return (
    <ScreenContainer topPadding={24} bottomPadding={32}>
      <View style={{ width: '100%', maxWidth: 560, gap: 24 }}>
        <View style={{ gap: 10 }}>
          <Text style={{ fontSize: 13, lineHeight: 18, fontWeight: '600', color: PlatformColor('secondaryLabel') }}>
            AURORA SETUP
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
                    index <= step ? PlatformColor('tintColor') : PlatformColor('tertiarySystemBackground'),
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

        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
          {step > 0 ? (
            <Pressable
              onPress={back}
              accessibilityRole="button"
              style={{
                minHeight: 44,
                paddingHorizontal: 16,
                borderRadius: 14,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: PlatformColor('tertiarySystemBackground'),
              }}
            >
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('label') }}>Back</Text>
            </Pressable>
          ) : null}

          <View style={{ flex: 1 }} />

          <Button
            title={step === TOTAL_STEPS - 1 ? 'Finish setup' : 'Continue'}
            variant="primary"
            onPress={next}
            disabled={!canAdvance}
          />
        </View>
      </View>
    </ScreenContainer>
  );
}
