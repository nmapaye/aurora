import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, Text, View, useColorScheme } from 'react-native';

import Button from '~/components/Button';
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

const HIT_TARGET = 44;

function formatDuration(ms: number) {
  return `${Math.max(0, Math.ceil(ms / 1000))}s`;
}

function formatReaction(reactionMs: number | null) {
  return reactionMs === null ? '—' : `${reactionMs} ms`;
}

export default function VigilanceTestScreen() {
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const addVigilanceSession = useStore((s) => s.addVigilanceSession);
  const [taskState, setTaskState] = useState<VigilanceTaskState>(() =>
    createVigilanceTaskState()
  );
  const [savedSessionId, setSavedSessionId] = useState<string | null>(null);
  const [tickNow, setTickNow] = useState<number>(Date.now());
  const savedRef = useRef(false);

  useEffect(() => {
    if (taskState.phase !== 'running') return undefined;
    const timer = setInterval(() => {
      const now = Date.now();
      setTickNow(now);
      setTaskState((current) => advanceVigilanceTask(current, now));
    }, 100);
    return () => clearInterval(timer);
  }, [taskState.phase]);

  useEffect(() => {
    if (
      taskState.phase !== 'complete' ||
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
    addVigilanceSession(session);
    savedRef.current = true;
    setSavedSessionId(sessionId);
  }, [addVigilanceSession, taskState]);

  const latestSession = useStore((s) =>
    savedSessionId
      ? s.vigilanceSessions.find((session) => session.id === savedSessionId) ?? null
      : null
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
            (trial) => trial.outcome === 'lapse'
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
    savedRef.current = false;
    setSavedSessionId(null);
    const now = Date.now();
    setTickNow(now);
    setTaskState(startVigilanceTask(now));
  };

  const handleTap = () => {
    const now = Date.now();
    setTickNow(now);
    setTaskState((current) => registerVigilanceTap(current, now));
  };

  return (
    <View
      style={{
        flex: 1,
        backgroundColor: palette.screen,
        paddingHorizontal: 16,
        paddingTop: 20,
        paddingBottom: 32,
      }}
    >
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          marginBottom: 20,
        }}
      >
        <Button title="Close" variant="outline" onPress={goBack} />
        <View style={{ flex: 1 }} />
        <View
          style={{
            minHeight: HIT_TARGET,
            paddingHorizontal: 14,
            borderRadius: 999,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: palette.neutralButton,
            borderWidth: 1,
            borderColor: palette.neutralButtonBorder,
          }}
        >
          <Text
            style={{
              fontSize: 15,
              lineHeight: 20,
              color: palette.textPrimary,
              fontWeight: '600',
            }}
          >
            {formatDuration(remainingMs)}
          </Text>
        </View>
      </View>

      <View style={{ gap: 16, flex: 1 }}>
        <View
          style={{
            backgroundColor: palette.card,
            borderRadius: 18,
            padding: 18,
            borderWidth: 1,
            borderColor: palette.cardBorder,
            gap: 8,
          }}
        >
          <Text
            style={{
              fontSize: 28,
              lineHeight: 34,
              fontWeight: '700',
              color: palette.textPrimary,
            }}
          >
            Vigilance Test
          </Text>
          <Text
            style={{
              fontSize: 15,
              lineHeight: 20,
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
            borderRadius: 24,
            padding: 24,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor:
              taskState.phase === 'complete'
                ? palette.card
                : currentCueVisible
                ? palette.primaryButton
                : palette.neutralButton,
            borderWidth: 2,
            borderColor:
              taskState.phase === 'complete'
                ? palette.cardBorder
                : currentCueVisible
                ? palette.primaryButton
                : palette.neutralButtonBorder,
          }}
        >
          {taskState.phase === 'instructions' ? (
            <View style={{ gap: 14, alignItems: 'center' }}>
              <Text
                style={{
                  fontSize: 24,
                  lineHeight: 30,
                  fontWeight: '700',
                  color: palette.textPrimary,
                  textAlign: 'center',
                }}
              >
                Measure your attentiveness
              </Text>
              <Text
                style={{
                  fontSize: 16,
                  lineHeight: 22,
                  color: palette.textSecondary,
                  textAlign: 'center',
                }}
              >
                Wait for the cue, then tap the active area as quickly as you can.
              </Text>
              <Button title="Start test" variant="primary" onPress={startSession} />
            </View>
          ) : taskState.phase === 'running' ? (
            <View style={{ gap: 14, alignItems: 'center' }}>
              <Text
                style={{
                  fontSize: 16,
                  lineHeight: 22,
                  color: currentCueVisible
                    ? palette.primaryButtonText
                    : palette.textSecondary,
                }}
              >
                {currentCueVisible ? 'Cue live' : 'Hold steady'}
              </Text>
              <Text
                style={{
                  fontSize: 42,
                  lineHeight: 48,
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
                  fontSize: 15,
                  lineHeight: 20,
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
            <View style={{ gap: 16, alignItems: 'center', width: '100%' }}>
              <Text
                style={{
                  fontSize: 16,
                  lineHeight: 22,
                  color: palette.textSecondary,
                }}
              >
                Session complete
              </Text>
              <Text
                style={{
                  fontSize: 48,
                  lineHeight: 56,
                  fontWeight: '700',
                  color: palette.textPrimary,
                }}
              >
                {latestSession.score}
              </Text>
              <Text
                style={{
                  fontSize: 24,
                  lineHeight: 30,
                  fontWeight: '600',
                  color: palette.textPrimary,
                }}
              >
                {latestSession.rating}
              </Text>
              <View
                style={{
                  width: '100%',
                  gap: 10,
                  backgroundColor: palette.neutralButton,
                  borderRadius: 18,
                  padding: 16,
                  borderWidth: 1,
                  borderColor: palette.neutralButtonBorder,
                }}
              >
                <Text
                  style={{ fontSize: 15, lineHeight: 20, color: palette.textPrimary }}
                >
                  Median reaction: {formatReaction(latestSession.medianReactionMs)}
                </Text>
                <Text
                  style={{ fontSize: 15, lineHeight: 20, color: palette.textPrimary }}
                >
                  Fastest reaction: {formatReaction(latestSession.fastestReactionMs)}
                </Text>
                <Text
                  style={{ fontSize: 15, lineHeight: 20, color: palette.textPrimary }}
                >
                  Lapses: {latestSession.lapseCount} • False starts:{' '}
                  {latestSession.falseStartCount}
                </Text>
              </View>
              <View style={{ flexDirection: 'row', gap: 12 }}>
                <Button title="Run again" variant="primary" onPress={startSession} />
                <Button title="Done" variant="outline" onPress={goBack} />
              </View>
            </View>
          ) : null}
        </Pressable>

        <View style={{ flexDirection: 'row', gap: 12 }}>
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
                borderRadius: 16,
                borderWidth: 1,
                borderColor: palette.cardBorder,
                padding: 14,
              }}
            >
              <Text
                style={{
                  fontSize: 14,
                  lineHeight: 18,
                  color: palette.textSecondary,
                  marginBottom: 4,
                }}
              >
                {item.label}
              </Text>
              <Text
                style={{
                  fontSize: 22,
                  lineHeight: 28,
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
