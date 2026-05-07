import type { Dose, SleepSession } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';

const dayMs = 86_400_000;
const hourMs = 3_600_000;

function startOfToday(now: number) {
  const date = new Date(now);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

export function createDemoSnapshot(now = Date.now()): {
  doses: Dose[];
  sleeps: SleepSession[];
  vigilanceSessions: VigilanceSession[];
} {
  const today = startOfToday(now);
  const dosePattern = [
    { day: 13, hour: 8.25, mg: 95, source: 'Demo drip' },
    { day: 13, hour: 13.5, mg: 60, source: 'Demo matcha' },
    { day: 12, hour: 9, mg: 95, source: 'Demo drip' },
    { day: 11, hour: 8.5, mg: 70, source: 'Demo tea' },
    { day: 10, hour: 14, mg: 80, source: 'Demo cold brew' },
    { day: 9, hour: 9.25, mg: 95, source: 'Demo drip' },
    { day: 8, hour: 12.75, mg: 60, source: 'Demo matcha' },
    { day: 7, hour: 8.75, mg: 95, source: 'Demo drip' },
    { day: 6, hour: 15.25, mg: 40, source: 'Demo tea' },
    { day: 5, hour: 9, mg: 120, source: 'Demo espresso' },
    { day: 4, hour: 13.25, mg: 60, source: 'Demo matcha' },
    { day: 3, hour: 8.5, mg: 95, source: 'Demo drip' },
    { day: 2, hour: 14.5, mg: 80, source: 'Demo cold brew' },
    { day: 1, hour: 9.25, mg: 95, source: 'Demo drip' },
    { day: 0, hour: 8.5, mg: 95, source: 'Demo drip' },
    { day: 0, hour: 12.25, mg: 60, source: 'Demo matcha' },
  ];

  const doses = dosePattern.map((item, index) => ({
    id: `demo:dose:${index}`,
    timestamp: today - item.day * dayMs + item.hour * hourMs,
    mg: item.mg,
    source: item.source,
    note: 'Demo sample',
  }));

  const sleeps = Array.from({ length: 10 }).map((_, index) => {
    const dayStart = today - index * dayMs;
    const start = dayStart - 1.25 * hourMs;
    const end = dayStart + (6.75 + (index % 3) * 0.25) * hourMs;
    return {
      id: `demo:sleep:${index}`,
      start,
      end,
      type: 'sleep' as const,
    };
  });

  const vigilanceSessions: VigilanceSession[] = [0, 1, 2].map((index) => {
    const completedAt = today - index * 2 * dayMs + 15 * hourMs;
    const median = 258 + index * 18;
    const score = 78 - index * 5;
    return {
      id: `demo:vigilance:${index}`,
      startedAt: completedAt - 60_000,
      completedAt,
      durationMs: 60_000,
      trialCount: 14,
      validReactionCount: 13 - index,
      falseStartCount: index === 2 ? 1 : 0,
      lapseCount: index,
      medianReactionMs: median,
      meanReactionMs: median + 8,
      fastestReactionMs: median - 47,
      reactionStdDevMs: 54 + index * 9,
      score,
      rating: score >= 80 ? 'Sharp' : score >= 60 ? 'Steady' : 'Slipping',
    };
  });

  return { doses, sleeps, vigilanceSessions };
}

export const mockDoses = createDemoSnapshot().doses.slice(0, 2);
export const mockSleeps = createDemoSnapshot().sleeps.slice(0, 1);
