import React, { useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Animated,
  Easing,
  ScrollView,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import AppIcon from '~/components/AppIcon';
import BrandHorizon from '~/components/BrandHorizon';
import BrandMark from '~/components/BrandMark';
import Button from '~/components/Button';
import { Divider, Eyebrow, Surface } from '~/components/ui';
import {
  describeHealthAccess,
  describeSetupNextAction,
  describeSleepSource,
  formatSleepTarget,
  getOnboardingLayoutMode,
  getOnboardingStepCopy,
  getSetupStepState,
  ONBOARDING_STEP_COUNT,
  type SetupStepState,
} from '~/features/onboarding/presentation';
import useAppScheme from '~/hooks/useAppScheme';
import useReduceMotion from '~/hooks/useReduceMotion';
import StepPermissions from '~/screens/Onboarding/steps/StepPermissions';
import StepSleepTarget from '~/screens/Onboarding/steps/StepSleepTarget';
import StepSources from '~/screens/Onboarding/steps/StepSources';
import AppleHealth, { makeHealthSleepSessionId } from '~/services/platform/health/appleHealth';
import { requestHealthPermissions } from '~/services/permissions';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import {
  borders,
  eyebrowText,
  fontScaling,
  getMotionDuration,
  iconSizes,
  motion,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';

const STACKED_MAX_WIDTH = 560;
const SPLIT_MAX_WIDTH = 1040;

export default function OnboardingScreen() {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const insets = useSafeAreaInsets();
  const { width, fontScale } = useWindowDimensions();
  const reduceMotion = useReduceMotion();
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

  const isLastStep = step === ONBOARDING_STEP_COUNT - 1;
  const canAdvance =
    !isLastStep ||
    onboarding.source === 'manual' ||
    onboarding.permissionStatus !== 'idle';
  const split = getOnboardingLayoutMode({ width, fontScale }) === 'split';
  const copy = getOnboardingStepCopy(step, onboarding.source);

  // Fade each new step in. Under Reduce Motion the fade is shorter and the
  // content does not move.
  const entrance = useRef(new Animated.Value(1)).current;
  const latest = useRef({ reduceMotion, title: copy.title });
  latest.current = { reduceMotion, title: copy.title };
  const mounted = useRef(false);
  const scrollRef = useRef<ScrollView>(null);
  useEffect(() => {
    if (!mounted.current) {
      mounted.current = true;
      return undefined;
    }
    // The action stays pinned, so start each step at its heading rather than
    // wherever the previous step was scrolled.
    scrollRef.current?.scrollTo({ y: 0, animated: false });
    AccessibilityInfo.announceForAccessibility(
      `Step ${step + 1} of ${ONBOARDING_STEP_COUNT}. ${latest.current.title}`,
    );
    entrance.setValue(0);
    const animation = Animated.timing(entrance, {
      toValue: 1,
      duration: getMotionDuration('gentle', latest.current.reduceMotion),
      easing: Easing.out(Easing.cubic),
      useNativeDriver: true,
    });
    animation.start();
    return () => animation.stop();
  }, [entrance, step]);

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
    if (!isLastStep) {
      setStep((current) => current + 1);
      return;
    }
    completeOnboarding();
  };
  const back = () => setStep((current) => Math.max(0, current - 1));

  const summaryRows = [0, 1, 2].map((index) => ({
    label: getOnboardingStepCopy(index, onboarding.source).summaryLabel,
    value:
      index === 0
        ? formatSleepTarget(targetSleep).spoken
        : index === 1
          ? describeSleepSource(onboarding.source)
          : describeHealthAccess(onboarding.source, onboarding.permissionStatus),
    state: getSetupStepState(index, step),
  }));

  const stepBody = (
    <Animated.View
      style={{
        gap: spacing.xl,
        opacity: entrance,
        transform: reduceMotion
          ? []
          : [
              {
                translateY: entrance.interpolate({
                  inputRange: [0, 1],
                  outputRange: [motion.entranceOffset, 0],
                }),
              },
            ],
      }}
    >
      <StepHeading
        eyebrow={copy.eyebrow}
        title={copy.title}
        body={copy.body}
      />

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

      {isLastStep ? (
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

      {isLastStep ? (
        <SampleDataOption
          disabled={requestingPermission}
          onLoad={loadDemoData}
        />
      ) : null}
    </Animated.View>
  );

  const nextActionNote = isLastStep ? (
    <Text
      accessibilityLiveRegion="polite"
      maxFontSizeMultiplier={fontScaling.body}
      style={{ ...typeRamp.footnote, color: palette.textSecondary }}
    >
      {describeSetupNextAction({
        source: onboarding.source,
        permissionStatus: onboarding.permissionStatus,
        importStatus: healthSync.importStatus,
        importedCount: healthSync.importedCount,
      })}
    </Text>
  ) : null;

  const actions = (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        gap: spacing.sm,
      }}
    >
      {step > 0 ? (
        <Button title="Back" variant="plain" onPress={back} />
      ) : null}
      <Button
        title={isLastStep ? 'Finish setup' : 'Continue'}
        variant="primary"
        onPress={next}
        disabled={!canAdvance}
        style={{ flex: 1, minHeight: 52, borderRadius: radii.capsule }}
      />
    </View>
  );

  const progress = <SetupProgress step={step} />;

  return (
    <View
      testID="onboarding-root"
      style={{ flex: 1, backgroundColor: palette.screen }}
    >
      <ScrollView
        ref={scrollRef}
        testID="onboarding-scroll"
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        style={{ flex: 1 }}
        contentContainerStyle={{
          flexGrow: 1,
          alignItems: 'center',
          justifyContent: split ? 'center' : 'flex-start',
          paddingHorizontal: split ? spacing.xxl * 1.5 : spacing.xl,
          paddingTop: split ? spacing.xxl : spacing.lg,
          // Stacked: the action bar below owns the bottom safe area.
          paddingBottom: split ? insets.bottom + spacing.xl : spacing.xl,
        }}
      >
        {split ? (
          <View
            testID="onboarding-split-layout"
            style={{
              width: '100%',
              maxWidth: SPLIT_MAX_WIDTH,
              flexDirection: 'row',
              alignItems: 'flex-start',
              gap: spacing.xxl * 1.5,
            }}
          >
            <View style={{ flex: 1, gap: spacing.xl, paddingTop: spacing.xl }}>
              <BrandLockup markSize={40} />
              <BrandHorizon maxWidth={420} />
              <View style={{ gap: spacing.sm }}>
                <Text
                  accessibilityRole="header"
                  maxFontSizeMultiplier={fontScaling.hero}
                  style={{
                    fontSize: 34,
                    fontWeight: '600',
                    color: palette.textPrimary,
                  }}
                >
                  Three choices, then you're in.
                </Text>
                <IntroCopy />
              </View>
              <SetupSummary rows={summaryRows} />
            </View>
            <Surface
              radius={radii.hero + spacing.xs}
              style={{ flex: 1.15, padding: spacing.xxl, gap: spacing.xl }}
            >
              {progress}
              {stepBody}
              <View style={{ gap: spacing.sm }}>
                {nextActionNote}
                {actions}
              </View>
            </Surface>
          </View>
        ) : (
          <View
            testID="onboarding-stacked-layout"
            style={{
              width: '100%',
              maxWidth: STACKED_MAX_WIDTH,
              gap: spacing.xl,
            }}
          >
            <BrandLockup markSize={32} />
            {step === 0 ? (
              <View style={{ gap: spacing.md }}>
                <BrandHorizon maxWidth={300} />
                <IntroCopy />
              </View>
            ) : null}
            {progress}
            {stepBody}
            {nextActionNote}
          </View>
        )}
      </ScrollView>
      {split ? null : (
        // Pinned below the form rather than over it, so the action stays in
        // reach at any text size without covering presets or step content.
        <View
          testID="onboarding-action-bar"
          style={{
            alignItems: 'center',
            paddingHorizontal: spacing.xl,
            paddingTop: spacing.sm,
            paddingBottom: Math.max(insets.bottom, spacing.md),
            borderTopWidth: borders.hairline,
            borderTopColor: palette.separator,
            backgroundColor: palette.screen,
          }}
        >
          <View style={{ width: '100%', maxWidth: STACKED_MAX_WIDTH }}>
            {actions}
          </View>
        </View>
      )}
    </View>
  );
}

function BrandLockup({ markSize }: { markSize: number }) {
  const palette = getAppPalette(useAppScheme());
  return (
    <View
      accessible
      accessibilityRole="header"
      accessibilityLabel="Aurora"
      style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xs }}
    >
      <BrandMark size={markSize} />
      <Text
        maxFontSizeMultiplier={fontScaling.hero}
        style={{
          ...typeRamp.title3,
          fontWeight: '600',
          letterSpacing: 0.4,
          color: palette.textPrimary,
        }}
      >
        Aurora
      </Text>
    </View>
  );
}

function IntroCopy() {
  const palette = getAppPalette(useAppScheme());
  return (
    <Text
      maxFontSizeMultiplier={fontScaling.body}
      style={{ ...typeRamp.body, color: palette.textSecondary }}
    >
      Aurora estimates how caffeine and recent sleep shape your alertness
      through the day. It is a planning aid, not medical advice.
    </Text>
  );
}

function SetupProgress({ step }: { step: number }) {
  const palette = getAppPalette(useAppScheme());
  const label = `Step ${step + 1} of ${ONBOARDING_STEP_COUNT}`;
  return (
    <View
      accessible
      accessibilityRole="progressbar"
      accessibilityLabel="Setup progress"
      accessibilityValue={{
        min: 1,
        max: ONBOARDING_STEP_COUNT,
        now: step + 1,
        text: label,
      }}
      style={{ gap: spacing.xs }}
    >
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...eyebrowText, color: palette.textSecondary }}
      >
        {label}
      </Text>
      <View style={{ flexDirection: 'row', gap: spacing.xs }}>
        {Array.from({ length: ONBOARDING_STEP_COUNT }).map((_, index) => (
          <View
            key={index}
            style={{
              flex: 1,
              height: 4,
              borderRadius: radii.capsule,
              backgroundColor:
                index <= step ? palette.tint : palette.cardBorder,
            }}
          />
        ))}
      </View>
    </View>
  );
}

function StepHeading({
  eyebrow,
  title,
  body,
}: {
  eyebrow: string;
  title: string;
  body: string;
}) {
  const palette = getAppPalette(useAppScheme());
  return (
    <View style={{ gap: spacing.sm }}>
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...eyebrowText, color: palette.tint }}
      >
        {eyebrow}
      </Text>
      <Text
        accessibilityRole="header"
        maxFontSizeMultiplier={fontScaling.hero}
        style={{
          fontSize: 30,
          fontWeight: '600',
          color: palette.textPrimary,
        }}
      >
        {title}
      </Text>
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...typeRamp.body, color: palette.textSecondary }}
      >
        {body}
      </Text>
    </View>
  );
}

const stateText: Record<SetupStepState, string> = {
  done: 'Done',
  current: 'Current step',
  upcoming: 'Up next',
};

function SetupSummary({
  rows,
}: {
  rows: { label: string; value: string; state: SetupStepState }[];
}) {
  const palette = getAppPalette(useAppScheme());
  return (
    <View testID="onboarding-setup-summary" style={{ gap: spacing.sm }}>
      <Eyebrow text="Your setup" />
      <Surface variant="muted" style={{ paddingVertical: spacing.xs }}>
        {rows.map((row, index) => (
          <View key={row.label}>
            {index > 0 ? <Divider inset={iconSizes.button + spacing.sm} /> : null}
            <View
              accessible
              accessibilityLabel={`${row.label}, ${row.value}. ${stateText[row.state]}.`}
              style={{
                flexDirection: 'row',
                alignItems: 'center',
                gap: spacing.sm,
                minHeight: 56,
                paddingVertical: spacing.xs,
              }}
            >
              <StepMarker index={index} state={row.state} />
              <View style={{ flex: 1, gap: spacing.xxs }}>
                <Text
                  maxFontSizeMultiplier={fontScaling.body}
                  style={{
                    ...typeRamp.footnote,
                    fontWeight: '600',
                    color: palette.textSecondary,
                  }}
                >
                  {row.label}
                </Text>
                <Text
                  maxFontSizeMultiplier={fontScaling.body}
                  style={{
                    ...typeRamp.headline,
                    color:
                      row.state === 'upcoming'
                        ? palette.textTertiary
                        : palette.textPrimary,
                  }}
                >
                  {row.value}
                </Text>
              </View>
            </View>
          </View>
        ))}
      </Surface>
    </View>
  );
}

function StepMarker({ index, state }: { index: number; state: SetupStepState }) {
  const palette = getAppPalette(useAppScheme());
  if (state === 'done') {
    return (
      <AppIcon
        name="checkmark-circle"
        size={iconSizes.button}
        color={palette.tint}
      />
    );
  }
  const current = state === 'current';
  return (
    <View
      style={{
        width: iconSizes.button,
        height: iconSizes.button,
        borderRadius: radii.capsule,
        alignItems: 'center',
        justifyContent: 'center',
        borderWidth: current ? borders.selected : borders.hairline,
        borderColor: current ? palette.tint : palette.textTertiary,
        backgroundColor: current ? palette.selectionFill : 'transparent',
      }}
    >
      <Text
        allowFontScaling={false}
        style={{
          ...typeRamp.caption,
          fontWeight: '600',
          color: current ? palette.tint : palette.textTertiary,
        }}
      >
        {index + 1}
      </Text>
    </View>
  );
}

function SampleDataOption({
  disabled,
  onLoad,
}: {
  disabled: boolean;
  onLoad: () => void;
}) {
  const palette = getAppPalette(useAppScheme());
  return (
    <Surface variant="muted" style={{ gap: spacing.sm }}>
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...typeRamp.headline, color: palette.textPrimary }}
      >
        Prefer to look around first?
      </Text>
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...typeRamp.subheadline, color: palette.textSecondary }}
      >
        Finish setup with example nights and doses, labeled Sample Data
        throughout. Clear them anytime from Sleep.
      </Text>
      <Button
        title="Load Sample Data"
        variant="tinted"
        onPress={onLoad}
        disabled={disabled}
        style={{ alignSelf: 'flex-start' }}
      />
    </Surface>
  );
}
