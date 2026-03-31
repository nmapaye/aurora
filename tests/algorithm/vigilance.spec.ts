import {
  advanceVigilanceTask,
  buildVigilanceSession,
  registerVigilanceTap,
  scoreVigilanceSession,
  startVigilanceTask,
} from '~/domain/vigilance';

describe('vigilance scoring and task flow', () => {
  it('rates a fast and consistent session as sharp', () => {
    const result = scoreVigilanceSession({
      trialCount: 14,
      validReactionCount: 13,
      falseStartCount: 0,
      lapseCount: 1,
      medianReactionMs: 238,
      meanReactionMs: 244,
      fastestReactionMs: 220,
      reactionStdDevMs: 34,
    });

    expect(result.score).toBeGreaterThanOrEqual(80);
    expect(result.rating).toBe('Sharp');
  });

  it('drops the score for lapse-heavy and false-start-heavy sessions', () => {
    const result = scoreVigilanceSession({
      trialCount: 10,
      validReactionCount: 4,
      falseStartCount: 4,
      lapseCount: 6,
      medianReactionMs: 470,
      meanReactionMs: 490,
      fastestReactionMs: 310,
      reactionStdDevMs: 175,
    });

    expect(result.score).toBeLessThan(40);
    expect(result.rating).toBe('Fatigued');
  });

  it('treats sub-150ms taps as false starts and 500ms taps as lapses', () => {
    let state = startVigilanceTask(1_000, 0);
    state = advanceVigilanceTask(state, 3_000, 0);
    state = registerVigilanceTap(state, 3_120, 0);
    expect(state.falseStartCount).toBe(1);
    expect(state.trialResults).toHaveLength(0);

    state = advanceVigilanceTask(state, 5_120, 0);
    state = registerVigilanceTap(state, 5_620, 0);
    expect(state.trialResults).toEqual([{ outcome: 'lapse', reactionMs: 500 }]);
  });

  it('records missed cues as lapses and builds a persisted summary', () => {
    let state = startVigilanceTask(10_000, 0);
    state = advanceVigilanceTask(state, 12_000, 0);
    state = advanceVigilanceTask(state, 13_001, 0);

    expect(state.trialResults).toEqual([{ outcome: 'lapse', reactionMs: null }]);

    const session = buildVigilanceSession({
      id: 'vig-1',
      startedAt: 10_000,
      completedAt: 70_000,
      trialResults: [
        { outcome: 'valid', reactionMs: 260 },
        { outcome: 'valid', reactionMs: 290 },
        ...state.trialResults,
      ],
      falseStartCount: 1,
    });

    expect(session.trialCount).toBe(3);
    expect(session.validReactionCount).toBe(2);
    expect(session.lapseCount).toBe(1);
    expect(session.falseStartCount).toBe(1);
    expect(session.medianReactionMs).toBe(275);
    expect(session.score).toBeGreaterThan(0);
  });
});
