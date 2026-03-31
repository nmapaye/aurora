export const VIGILANCE_TEST_DURATION_MS = 60_000;
export const VIGILANCE_MIN_DELAY_MS = 2_000;
export const VIGILANCE_MAX_DELAY_MS = 5_000;
export const VIGILANCE_RESPONSE_WINDOW_MS = 1_000;
export const VIGILANCE_FALSE_START_MS = 150;
export const VIGILANCE_LAPSE_MS = 500;

export type VigilanceRating = 'Sharp' | 'Steady' | 'Slipping' | 'Fatigued';

export type VigilanceSession = {
  id: string;
  startedAt: number;
  completedAt: number;
  durationMs: number;
  trialCount: number;
  validReactionCount: number;
  falseStartCount: number;
  lapseCount: number;
  medianReactionMs: number | null;
  meanReactionMs: number | null;
  fastestReactionMs: number | null;
  reactionStdDevMs: number | null;
  score: number;
  rating: VigilanceRating;
};

export type VigilanceTrialResult =
  | { outcome: 'valid'; reactionMs: number }
  | { outcome: 'lapse'; reactionMs: number | null };

export type VigilanceTaskFeedback = 'false_start' | 'missed' | 'slow' | null;

export type VigilanceTaskState = {
  phase: 'instructions' | 'running' | 'complete';
  startedAt: number | null;
  endsAt: number | null;
  nextCueAt: number | null;
  cueShownAt: number | null;
  trialResults: VigilanceTrialResult[];
  falseStartCount: number;
  feedback: VigilanceTaskFeedback;
};

type VigilanceSummaryMetrics = Pick<
  VigilanceSession,
  | 'trialCount'
  | 'validReactionCount'
  | 'falseStartCount'
  | 'lapseCount'
  | 'medianReactionMs'
  | 'meanReactionMs'
  | 'fastestReactionMs'
  | 'reactionStdDevMs'
>;

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function normalizeDescending(value: number, best: number, worst: number) {
  if (value <= best) return 100;
  if (value >= worst) return 0;
  return Math.round(((worst - value) / (worst - best)) * 100);
}

function roundOrNull(value: number | null) {
  return value === null ? null : Math.round(value);
}

function mean(values: number[]) {
  if (values.length === 0) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function median(values: number[]) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
  return sorted[mid];
}

function standardDeviation(values: number[]) {
  const avg = mean(values);
  if (avg === null || values.length === 0) return null;
  const variance =
    values.reduce((sum, value) => sum + (value - avg) ** 2, 0) / values.length;
  return Math.sqrt(variance);
}

export function getVigilanceDelayMs(randomValue = Math.random()) {
  const normalized = clamp(randomValue, 0, 0.999999);
  return Math.round(
    VIGILANCE_MIN_DELAY_MS +
      normalized * (VIGILANCE_MAX_DELAY_MS - VIGILANCE_MIN_DELAY_MS)
  );
}

export function scoreVigilanceSession(metrics: VigilanceSummaryMetrics): {
  score: number;
  rating: VigilanceRating;
} {
  const medianForScore = metrics.medianReactionMs ?? VIGILANCE_LAPSE_MS;
  const stdDevForScore = metrics.reactionStdDevMs ?? 180;
  const totalAttempts = Math.max(
    1,
    metrics.trialCount + metrics.falseStartCount
  );
  const lapseRate = metrics.lapseCount / totalAttempts;
  const falseStartRate = metrics.falseStartCount / totalAttempts;

  const speed = normalizeDescending(medianForScore, 220, 500);
  const consistency = normalizeDescending(stdDevForScore, 40, 180);
  const accuracy = clamp(
    Math.round(100 - lapseRate * 120 - falseStartRate * 60),
    0,
    100
  );

  const score = clamp(
    Math.round(speed * 0.5 + accuracy * 0.3 + consistency * 0.2),
    0,
    100
  );
  const rating: VigilanceRating =
    score >= 80
      ? 'Sharp'
      : score >= 60
      ? 'Steady'
      : score >= 40
      ? 'Slipping'
      : 'Fatigued';
  return { score, rating };
}

export function buildVigilanceSession(params: {
  id: string;
  startedAt: number;
  completedAt: number;
  trialResults: VigilanceTrialResult[];
  falseStartCount: number;
}): VigilanceSession {
  const validReactions = params.trialResults
    .filter(
      (result): result is Extract<VigilanceTrialResult, { outcome: 'valid' }> =>
        result.outcome === 'valid'
    )
    .map((result) => result.reactionMs);
  const lapseCount = params.trialResults.filter(
    (result) => result.outcome === 'lapse'
  ).length;

  const metrics: VigilanceSummaryMetrics = {
    trialCount: params.trialResults.length,
    validReactionCount: validReactions.length,
    falseStartCount: params.falseStartCount,
    lapseCount,
    medianReactionMs: roundOrNull(median(validReactions)),
    meanReactionMs: roundOrNull(mean(validReactions)),
    fastestReactionMs:
      validReactions.length > 0 ? Math.min(...validReactions) : null,
    reactionStdDevMs: roundOrNull(standardDeviation(validReactions)),
  };
  const scored = scoreVigilanceSession(metrics);

  return {
    id: params.id,
    startedAt: params.startedAt,
    completedAt: params.completedAt,
    durationMs: params.completedAt - params.startedAt,
    ...metrics,
    score: scored.score,
    rating: scored.rating,
  };
}

export function createVigilanceTaskState(): VigilanceTaskState {
  return {
    phase: 'instructions',
    startedAt: null,
    endsAt: null,
    nextCueAt: null,
    cueShownAt: null,
    trialResults: [],
    falseStartCount: 0,
    feedback: null,
  };
}

export function startVigilanceTask(
  now: number,
  randomValue = Math.random()
): VigilanceTaskState {
  return {
    phase: 'running',
    startedAt: now,
    endsAt: now + VIGILANCE_TEST_DURATION_MS,
    nextCueAt: now + getVigilanceDelayMs(randomValue),
    cueShownAt: null,
    trialResults: [],
    falseStartCount: 0,
    feedback: null,
  };
}

function scheduleNextCue(
  state: VigilanceTaskState,
  now: number,
  randomValue: number,
  feedback: VigilanceTaskFeedback
): VigilanceTaskState {
  return {
    ...state,
    cueShownAt: null,
    nextCueAt: now + getVigilanceDelayMs(randomValue),
    feedback,
  };
}

function finalizeTask(state: VigilanceTaskState): VigilanceTaskState {
  return {
    ...state,
    phase: 'complete',
    cueShownAt: null,
    nextCueAt: null,
  };
}

export function advanceVigilanceTask(
  state: VigilanceTaskState,
  now: number,
  randomValue = Math.random()
): VigilanceTaskState {
  if (state.phase !== 'running') return state;

  if (state.endsAt !== null && now >= state.endsAt) {
    if (state.cueShownAt !== null) {
      return finalizeTask({
        ...state,
        trialResults: [
          ...state.trialResults,
          { outcome: 'lapse', reactionMs: null },
        ],
        feedback: 'missed',
      });
    }
    return finalizeTask(state);
  }

  if (state.cueShownAt === null && state.nextCueAt !== null && now >= state.nextCueAt) {
    return {
      ...state,
      cueShownAt: state.nextCueAt,
      nextCueAt: null,
      feedback: null,
    };
  }

  if (
    state.cueShownAt !== null &&
    now - state.cueShownAt >= VIGILANCE_RESPONSE_WINDOW_MS
  ) {
    return scheduleNextCue(
      {
        ...state,
        trialResults: [
          ...state.trialResults,
          { outcome: 'lapse', reactionMs: null },
        ],
      },
      now,
      randomValue,
      'missed'
    );
  }

  return state;
}

export function registerVigilanceTap(
  state: VigilanceTaskState,
  now: number,
  randomValue = Math.random()
): VigilanceTaskState {
  if (state.phase !== 'running') return state;

  if (state.cueShownAt === null) {
    return {
      ...state,
      falseStartCount: state.falseStartCount + 1,
      feedback: 'false_start',
    };
  }

  const reactionMs = now - state.cueShownAt;
  if (reactionMs < VIGILANCE_FALSE_START_MS) {
    return scheduleNextCue(
      {
        ...state,
        falseStartCount: state.falseStartCount + 1,
      },
      now,
      randomValue,
      'false_start'
    );
  }

  if (reactionMs >= VIGILANCE_LAPSE_MS) {
    return scheduleNextCue(
      {
        ...state,
        trialResults: [
          ...state.trialResults,
          { outcome: 'lapse', reactionMs },
        ],
      },
      now,
      randomValue,
      'slow'
    );
  }

  return scheduleNextCue(
    {
      ...state,
      trialResults: [
        ...state.trialResults,
        { outcome: 'valid', reactionMs },
      ],
    },
    now,
    randomValue,
    null
  );
}
