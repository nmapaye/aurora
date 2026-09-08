import React, { useEffect, useMemo, useRef, useState } from 'react';
import { AppState, Pressable, Text, View } from 'react-native';

import Button from '~/components/Button';
import useAppScheme from '~/hooks/useAppScheme';
import { goBack } from '~/navigation';
import {
  advanceVigilanceTask,
  buildVigilanceSession,
  createVigilanceTaskState,
  registerVigilanceTap,
  startVigilanceTask,
  type VigilanceTaskState,
  VIGILANCE_FALSE_START_MS,
  VIGILANCE_LAPSE_MS,
  VIGILANCE_TEST_DURATION_MS,
} from '~/domain/vigilance';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { numericText, radii, spacing, typeRamp } from '~/theme/tokens';

const HIT_TARGET = 44;

function formatDuration(ms: number) {
  return `${Math.max(0, Math.ceil(ms / 1000))}s`;
}

function formatReaction(reactionMs: number | null) {
  return reactionMs === null ? '—' : `${reactionMs} ms`;
}

export default function VigilanceTestScreen() {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const addVigilanceSession = useStore((s) => s.addVigilanceSession);
  const [taskState, setTaskState] = useState<VigilanceTaskState>(() =>
    createVigilanceTaskState(),
  );
  const [savedSessionId, setSavedSessionId] = useState<string | null>(null);
  const [tickNow, setTickNow] = useState<number>(Date.now());
  const savedRef = useRef(false);
  const runningRef = useRef(false);
  const [interrupted, setInterrupted] = useState(false);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active' || !runningRef.current) return;
      runningRef.current = false;
      setInterrupted(true);
      setTaskState(createVigilanceTaskState());
    });
    return () => subscription.remove();
  }, []);

  useEffect(() => {
    if (taskState.phase !== 'running') return undefined;
    const timer = setInterval(() => {
      if (!runningRef.current) return;
      const now = Date.now();
      setTickNow(now);
      setTaskState((current) => advanceVigilanceTask(current, now));
    }, 100);
    return () => clearInterval(timer);
  }, [taskState.phase]);

  useEffect(() => {
    if (
      taskState.phase !== 'complete' ||
      !runningRef.current ||
      savedRef.current ||
      taskState.startedAt === null
    ) {
      return;
    }
    const sessionId = `vig-${Date.now().toString(36)}-${Math.random()
      .toString(36)
      .slice(2, 8)}`;
    const session = buildVigilanceSession({
      id: sessionId,
      startedAt: taskState.startedAt,
      completedAt: Date.now(),
      trialResults: taskState.trialResults,
      falseStartCount: taskState.falseStartCount,
    });
    runningRef.current = false;
    addVigilanceSession(session);
    savedRef.current = true;
    setSavedSessionId(sessionId);
  }, [addVigilanceSession, taskState]);

  const latestSession = useStore((s) =>
    savedSessionId
      ? (s.vigilanceSessions.find((session) => session.id === savedSessionId) ??
        null)
      : null,
  );

  const remainingMs =
    taskState.phase === 'running' && taskState.endsAt !== null
      ? Math.max(0, taskState.endsAt - tickNow)
      : VIGILANCE_TEST_DURATION_MS;

  const currentCueVisible =
    taskState.phase === 'running' && taskState.cueShownAt !== null;

  const feedbackText = useMemo(() => {
    switch (taskState.feedback) {
      case 'false_start':
        return `Too early. Wait for the cue before tapping.`;
      case 'missed':
        return `Missed cue. A lapse was recorded.`;
      case 'slow':
        return `Slow response. Reactions at ${VIGILANCE_LAPSE_MS} ms or more count as lapses.`;
      default:
        return `Responses under ${VIGILANCE_FALSE_START_MS} ms count as false starts.`;
    }
  }, [taskState.feedback]);

  const headerSummary =
    taskState.phase === 'running'
      ? {
          trialCount: taskState.trialResults.length,
          falseStartCount: taskState.falseStartCount,
          lapseCount: taskState.trialResults.filter(
            (trial) => trial.outcome === 'lapse',
          ).length,
        }
      : latestSession
        ? {
            trialCount: latestSession.trialCount,
            falseStartCount: latestSession.falseStartCount,
            lapseCount: latestSession.lapseCount,
          }
        : {
            trialCount: 0,
            falseStartCount: 0,
            lapseCount: 0,
          };

  const startSession = () => {
    runningRef.current = true;
    setInterrupted(false);
    savedRef.current = false;
    setSavedSessionId(null);
    const now = Date.now();
    setTickNow(now);
    setTaskState(startVigilanceTask(now));
  };

  const handleTap = () => {
    if (!runningRef.current) return;
    const now = Date.now();
    setTickNow(now);
    setTaskState((current) => registerVigilanceTap(current, now));
  };

  return (
    <View
      style={{
        flex: 1,
        backgroundColor: palette.groupedBackground,
        paddingHorizontal: spacing.md,
        paddingTop: spacing.lg,
        paddingBottom: spacing.xxl,
      }}
    >
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          marginBottom: spacing.lg,
        }}
      >
        <Button title="Close" variant="plain" onPress={goBack} />
        <View style={{ flex: 1 }} />
        <View
          style={{
            minHeight: HIT_TARGET,
            paddingHorizontal: spacing.sm,
            borderRadius: radii.capsule,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: palette.cardMuted,
            borderWidth: scheme === 'dark' ? 0 : 1,
            borderColor: palette.neutralButtonBorder,
          }}
        >
          <Text
            style={{
              ...typeRamp.subheadline,
              color: palette.textPrimary,
              fontWeight: '600',
            }}
          >
            {formatDuration(remainingMs)}
          </Text>
        </View>
      </View>

      <View style={{ gap: spacing.md, flex: 1 }}>
        <View
          style={{
            backgroundColor: palette.card,
            borderRadius: radii.hero,
            padding: spacing.md,
            borderWidth: scheme === 'dark' ? 0 : 1,
            borderColor: palette.cardBorder,
            gap: spacing.xs,
          }}
        >
          <Text
            style={{
              ...typeRamp.title1,
              fontWeight: '700',
              color: palette.textPrimary,
            }}
          >
            Vigilance Test
          </Text>
          <Text
            style={{
              ...typeRamp.subheadline,
              color: palette.textSecondary,
            }}
          >
            Tap as soon as the screen changes. The test runs for 60 seconds and
            records false starts, lapses, and reaction speed.
          </Text>
        </View>

        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Vigilance test area"
          onPress={taskState.phase === 'running' ? handleTap : undefined}
          disabled={taskState.phase !== 'running'}
          style={{
            flex: 1,
            borderRadius: radii.hero,
            padding: spacing.xl,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor:
              taskState.phase === 'complete'
                ? palette.card
                : currentCueVisible
                  ? palette.primaryButton
                  : palette.neutralButton,
            borderWidth: scheme === 'dark' ? 0 : 2,
            borderColor:
              taskState.phase === 'complete'
                ? palette.cardBorder
                : currentCueVisible
                  ? palette.primaryButton
                  : palette.neutralButtonBorder,
          }}
        >
          {taskState.phase === 'instructions' ? (
            <View style={{ gap: spacing.sm, alignItems: 'center' }}>
              <Text
                style={{
                  ...typeRamp.title3,
                  fontWeight: '700',
                  color: palette.textPrimary,
                  textAlign: 'center',
                }}
              >
                Measure your attentiveness
              </Text>
              <Text
                style={{
                  ...typeRamp.body,
                  color: palette.textSecondary,
                  textAlign: 'center',
                }}
              >
                Wait for the cue, then tap the active area as quickly as you
                can.
              </Text>
              {interrupted && (
                <Text accessibilityRole="alert" accessibilityLiveRegion="assertive"
                  style={{ ...typeRamp.body, color: palette.textPrimary, textAlign: 'center' }}>
                  Test interrupted when the app became inactive. This run was not saved. Start a new test when you can stay in the app for 60 seconds.
                </Text>
              )}
              <Button
                title="Start Test"
                variant="primary"
                onPress={startSession}
              />
            </View>
          ) : taskState.phase === 'running' ? (
            <View style={{ gap: spacing.sm, alignItems: 'center' }}>
              <Text
                style={{
                  ...typeRamp.body,
                  color: currentCueVisible
                    ? palette.primaryButtonText
                    : palette.textSecondary,
                }}
              >
                {currentCueVisible ? 'Cue live' : 'Hold steady'}
              </Text>
              <Text
                style={{
                  ...numericText,
                  fontWeight: '700',
                  color: currentCueVisible
                    ? palette.primaryButtonText
                    : palette.textPrimary,
                  textAlign: 'center',
                }}
              >
                {currentCueVisible ? 'TAP!' : 'Wait…'}
              </Text>
              <Text
                style={{
                  ...typeRamp.subheadline,
                  color: currentCueVisible
                    ? palette.primaryButtonText
                    : palette.textSecondary,
                  textAlign: 'center',
                }}
              >
                {feedbackText}
              </Text>
            </View>
          ) : latestSession ? (
            <View
              style={{ gap: spacing.md, alignItems: 'center', width: '100%' }}
            >
              <Text
                style={{
                  ...typeRamp.body,
                  color: palette.textSecondary,
                }}
              >
                Session complete
              </Text>
              <Text
                style={{
                  ...numericText,
                  fontWeight: '700',
                  color: palette.textPrimary,
                }}
              >
                {latestSession.score}
              </Text>
              <Text
                style={{
                  ...typeRamp.title3,
                  fontWeight: '600',
                  color: palette.textPrimary,
                }}
              >
                {latestSession.rating}
              </Text>
              <View
                style={{
                  width: '100%',
                  gap: spacing.sm,
                  backgroundColor: palette.neutralButton,
                  borderRadius: radii.card,
                  padding: spacing.md,
                  borderWidth: scheme === 'dark' ? 0 : 1,
                  borderColor: palette.neutralButtonBorder,
                }}
              >
                <Text
                  style={{
                    ...typeRamp.subheadline,
                    color: palette.textPrimary,
                  }}
                >
                  Median reaction:{' '}
                  {formatReaction(latestSession.medianReactionMs)}
                </Text>
                <Text
                  style={{
                    ...typeRamp.subheadline,
                    color: palette.textPrimary,
                  }}
                >
                  Fastest reaction:{' '}
                  {formatReaction(latestSession.fastestReactionMs)}
                </Text>
                <Text
                  style={{
                    ...typeRamp.subheadline,
                    color: palette.textPrimary,
                  }}
                >
                  Lapses: {latestSession.lapseCount} • False starts:{' '}
                  {latestSession.falseStartCount}
                </Text>
              </View>
              <View style={{ flexDirection: 'row', gap: spacing.sm }}>
                <Button
                  title="Run Again"
                  variant="primary"
                  onPress={startSession}
                />
                <Button title="Done" variant="plain" onPress={goBack} />
              </View>
            </View>
          ) : null}
        </Pressable>

        <View style={{ flexDirection: 'row', gap: spacing.sm }}>
          {[
            { label: 'Trials', value: headerSummary.trialCount },
            { label: 'False starts', value: headerSummary.falseStartCount },
            { label: 'Lapses', value: headerSummary.lapseCount },
          ].map((item) => (
            <View
              key={item.label}
              style={{
                flex: 1,
                minHeight: HIT_TARGET,
                backgroundColor: palette.card,
                borderRadius: radii.card,
                borderWidth: scheme === 'dark' ? 0 : 1,
                borderColor: palette.cardBorder,
                padding: spacing.sm,
              }}
            >
              <Text
                style={{
                  ...typeRamp.subheadline,
                  color: palette.textSecondary,
                  marginBottom: spacing.xxs,
                }}
              >
                {item.label}
              </Text>
              <Text
                style={{
                  ...typeRamp.title3,
                  fontWeight: '700',
                  color: palette.textPrimary,
                }}
              >
                {item.value}
              </Text>
            </View>
          ))}
        </View>
      </View>
    </View>
  );
}
