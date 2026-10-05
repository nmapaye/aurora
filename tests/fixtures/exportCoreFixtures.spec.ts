// Writes the expected outputs the Swift AuroraCore tests compare against.
// Skipped unless AURORA_FIXTURE_OUT is set; run it once per time zone:
//   AURORA_FIXTURE_OUT=AuroraCore/Tests/AuroraCoreTests/Fixtures TZ=UTC npx jest tests/fixtures
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { buildVigilanceSession, scoreVigilanceSession } from '~/domain/vigilance';
import type { Dose, SleepSession } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import { createDemoSnapshot } from '~/features/sampleData/sampleData';
import {
  estimateAlertness,
  getCutoffAnnotation,
  describeAlertnessEstimate,
  describeCaffeineDay,
  hasCaffeineSignal,
} from '~/features/summary/presentation';
import {
  caffeineLoggedSignal,
  reactionTestSignal,
  sleepSignal,
} from '~/features/summary/signals';
import {
  getCaffeineImpact,
  getSleepPresentation,
  episodeSourceLabel,
} from '~/features/sleep/presentation';
import { caffeineTimingSignal, recentNightSignal } from '~/features/sleep/signals';
import { getInsightsPresentation } from '~/features/insights/presentation';
import { getLoggedTodaySummary, getRecentDoses } from '~/features/caffeine/presentation';
import {
  getDailyTotalRows,
  makeDailyTotalsCSV,
  makeDoseEntriesCSV,
  makeVigilanceSessionsCSV,
} from '~/services/storage/export';
import { kv } from '~/services/storage';
import { useStore } from '~/state/store';

const out = process.env.AURORA_FIXTURE_OUT;
const zone = process.env.TZ ?? 'UTC';
const HOUR = 3_600_000;
const DAY = 86_400_000;

// Deterministic text formatters, so fixtures don't depend on locale data.
const T = (ts: number) => `T${ts}`;
const D = (ts: number) => `D${ts}`;

// UTC instants; each time zone reads them as different local times.
const NOWS = [
  Date.UTC(2026, 8, 27, 16, 41), // Sep 27 2026
  Date.UTC(2026, 2, 8, 19, 0), // US DST starts that morning
  Date.UTC(2026, 10, 1, 20, 30), // US DST ends that morning
  Date.UTC(2026, 0, 1, 7, 59), // just before LA midnight rollover
  Date.UTC(2026, 6, 15, 3, 10),
];

function dataset(now: number) {
  const sample = createDemoSnapshot(now);
  const manualDoses: Dose[] = [
    { id: 'm1', timestamp: now - 30 * 60_000, mg: 95, source: 'Drip' },
    { id: 'm2', timestamp: now - 5 * HOUR, mg: 60, source: 'Espresso', note: ' morning ' },
    { id: 'm3', timestamp: now - 26 * HOUR, mg: 12.5, source: 'Tea "green"' },
    { id: 'm4', timestamp: now - 3 * DAY - 2 * HOUR, mg: 160, source: 'Energy' },
    { id: 'm5', timestamp: now + 2 * HOUR, mg: 80, source: 'Future' },
    { id: 'm6', timestamp: now - 20 * DAY, mg: 70 },
    { id: 'm7', timestamp: now - 9 * DAY - 4 * HOUR, mg: 40, source: 'pill' },
  ];
  const lastNightEnd = now - 6 * HOUR;
  const manualSleeps: SleepSession[] = [
    // Health stage fragments of one night, with a brief awakening.
    { id: `healthkit:sleep:${lastNightEnd - 7 * HOUR}:${lastNightEnd - 4 * HOUR}`, start: lastNightEnd - 7 * HOUR, end: lastNightEnd - 4 * HOUR, type: 'sleep' },
    { id: `healthkit:sleep:${lastNightEnd - 3.75 * HOUR}:${lastNightEnd}`, start: lastNightEnd - 3.75 * HOUR, end: lastNightEnd, type: 'sleep' },
    { id: 'manual:sleep:1:abc', start: now - 2 * DAY - 8 * HOUR, end: now - 2 * DAY - 1 * HOUR, type: 'sleep' },
    { id: 'manual:sleep:2:def', start: now - 2 * DAY + 2 * HOUR, end: now - 2 * DAY + 3 * HOUR, type: 'nap' },
    { id: 'sleep:1:2', start: now - 40 * DAY, end: now - 40 * DAY + 6 * HOUR, type: 'sleep' },
  ];
  return {
    doses: [...sample.doses, ...manualDoses],
    sleeps: [...sample.sleeps, ...manualSleeps],
    vigilance: [
      ...sample.vigilanceSessions,
      {
        ...sample.vigilanceSessions[0],
        id: 'vig-abc-123456',
        completedAt: now - 3 * HOUR,
        startedAt: now - 3 * HOUR - 60_000,
        score: 64,
        rating: 'Steady' as const,
        medianReactionMs: 301.4,
      },
    ] as VigilanceSession[],
  };
}

function scenario(now: number) {
  const { doses, sleeps, vigilance } = dataset(now);
  const prefs = { halfLife: 5, targetSleep: 8 };
  const probes = [now, now - 3 * HOUR, now + 4 * HOUR, now - 30 * HOUR];
  const week = getSleepPresentation(sleeps, 8, 'week', now);
  const month = getSleepPresentation(sleeps, 7.5, 'month', now);
  const dayStart = new Date(now).setHours(0, 0, 0, 0);
  const series = Array.from({ length: 25 }, (_, i) => ({ t: dayStart + i * HOUR, mg: (i * 7) % 30 }));
  return {
    now,
    dataset: { doses, sleeps, vigilance },
    alertness: probes.map((t) => {
      const estimate = estimateAlertness(t, doses, sleeps, prefs);
      return { t, estimate, text: describeAlertnessEstimate(estimate) };
    }),
    cutoff: [0, 9, 16, 23.6].map((cutoffHour) => ({
      cutoffHour,
      withDoses: getCutoffAnnotation({ now, cutoffHour, doses, formatTime: T }),
      withoutDoses: getCutoffAnnotation({ now, cutoffHour, doses: [], formatTime: T }),
    })),
    caffeineDay: {
      text: describeCaffeineDay({ series, doses, dayStart, dayEnd: dayStart + DAY, formatTime: T }),
      has: hasCaffeineSignal({ series, doses, dayStart, dayEnd: dayStart + DAY }),
    },
    sleepWeek: { ...week, dateRange: undefined, accessibilitySummary: undefined },
    sleepMonth: { ...month, dateRange: undefined, accessibilitySummary: undefined },
    impactWeek: getCaffeineImpact(sleeps, doses, 'week', now),
    impactMonth: getCaffeineImpact(sleeps, doses, 'month', now),
    timing: caffeineTimingSignal(sleeps, doses, now),
    timingFew: caffeineTimingSignal(sleeps.slice(0, 3), doses, now),
    recentNight: recentNightSignal(sleeps, 8, now, T, D),
    recentNightEmpty: recentNightSignal([], 8, now, T, D),
    episodeSources: episodeSourceLabel(['demo:sleep:1', 'manual:sleep:x', 'healthkit:sleep:1:2']),
    caffeineSignal: caffeineLoggedSignal(doses, now, T),
    caffeineSignalManual: caffeineLoggedSignal(doses.filter((d) => !d.id.startsWith('demo:')), now, T),
    sleepSignal: { ...sleepSignal(sleeps, 8, now, T), period: undefined },
    reactionSignal: { ...reactionTestSignal(vigilance, now), period: undefined },
    loggedToday: getLoggedTodaySummary(doses, now, T),
    recent: getRecentDoses(doses).map((dose) => dose.id),
    insights: (['7', '14', '30'] as const).map((range) => {
      const p = getInsightsPresentation(doses, vigilance, range, now);
      return {
        range,
        points: p.points,
        recordedDays: p.recordedDays,
        missingDays: p.missingDays,
        headline: p.headline,
        source: p.source,
        trend: p.trend,
        dayparts: p.dayparts,
        drinkMix: p.drinkMix,
        reaction: { ...p.reaction, period: undefined },
        latestRecordedIndex: p.latestRecordedIndex,
        isEmpty: p.isEmpty,
        previousRecordedDays: p.previous.recordedDays,
        previousAverage: p.previous.averageMg,
      };
    }),
    export: {
      dailyRows: getDailyTotalRows(doses, now),
      dailyCSV: makeDailyTotalsCSV(getDailyTotalRows(doses, now)),
      doseCSV: makeDoseEntriesCSV(doses),
      vigilanceCSV: makeVigilanceSessionsCSV(vigilance),
    },
  };
}

function vigilanceCases() {
  const trials = [
    [{ outcome: 'valid', reactionMs: 240 }, { outcome: 'valid', reactionMs: 301 }, { outcome: 'lapse', reactionMs: null }],
    [{ outcome: 'valid', reactionMs: 220 }, { outcome: 'valid', reactionMs: 260 }],
    [],
    [{ outcome: 'lapse', reactionMs: 640 }, { outcome: 'valid', reactionMs: 333 }, { outcome: 'valid', reactionMs: 287 }, { outcome: 'valid', reactionMs: 412 }],
  ] as const;
  return trials.map((trialResults, index) =>
    buildVigilanceSession({
      id: `case-${index}`,
      startedAt: 1_000,
      completedAt: 61_000 + index,
      trialResults: trialResults as never,
      falseStartCount: index,
    }),
  ).concat([]).map((session) => ({ session, rescored: scoreVigilanceSession(session) }));
}

const LEGACY_NOW = Date.UTC(2026, 8, 27, 12, 0);
const legacyBlobs: Record<string, unknown> = {
  v1: {
    version: 1,
    state: {
      doses: [{ id: 'a', timestamp: 1, mg: 95 }, { id: '', timestamp: 2, mg: 5 }, { id: 'b', timestamp: 3, mg: -1 }],
      sleeps: [{ id: 'sleep:1000:2000', start: 1000, end: 2000, type: 'sleep' }],
      prefs: { halfLife: 6, cutoffHour: 'x' },
      onboarding: { completed: true, permissionStatus: 'granted' },
      healthSync: { lastMessage: 'Imported 3 nights of sleep from Health.' },
    },
  },
  v4: {
    version: 4,
    state: {
      onboarding: { completed: true, summaryWalkthroughCompleted: true, source: 'manual', permissionStatus: 'denied' },
      healthSync: { importedCount: 2, lastMessage: 'Health refresh failed. boom' },
      vigilanceSessions: [{ id: 'v', startedAt: 1, completedAt: 2, score: 40, rating: 'Fatigued' }],
      demoMode: true,
      appearanceMode: 'dark',
    },
  },
  v5: {
    version: 5,
    state: {
      onboarding: { completed: true, permissionStatus: 'granted', appWalkthroughStep: 4 },
      healthSync: { lastMessage: 'health connected' },
    },
  },
  v6importing: {
    version: 6,
    state: {
      onboarding: { completed: true, permissionStatus: 'granted', appWalkthroughStep: 12.7, appWalkthroughCompleted: false },
      healthSync: { importStatus: 'importing', importedCount: 4 },
      sleeps: [
        { id: `healthkit:sleep:${LEGACY_NOW - 200 * DAY}:${LEGACY_NOW - 199 * DAY}`, start: LEGACY_NOW - 200 * DAY, end: LEGACY_NOW - 199 * DAY, type: 'sleep' },
        { id: 'manual:sleep:5:x', start: LEGACY_NOW - 300 * DAY, end: LEGACY_NOW - 299 * DAY, type: 'sleep' },
        { id: 'healthkit:sleep:10.4:20.6', start: 10.4, end: 20.6, type: 'nap' },
        { id: 'bad', start: 5, end: 4, type: 'sleep' },
      ],
      prefs: { halfLife: 4.5, targetSleep: 7.5, dailyLimitMg: 300, cutoffHour: 14, notifyCutoff: true, tz: 'Europe/Paris' },
    },
  },
  v6unknown: {
    version: 6,
    state: { onboarding: { permissionStatus: 'granted' }, healthSync: { importStatus: 'weird' } },
  },
};

(out ? describe : describe.skip)('export AuroraCore fixtures', () => {
  beforeAll(() => mkdirSync(out!, { recursive: true }));

  it('writes scenario fixtures', () => {
    const fixture = { zone, scenarios: NOWS.map(scenario), vigilance: vigilanceCases() };
    writeFileSync(join(out!, `core-${zone.replace(/\//g, '_')}.json`), JSON.stringify(fixture));
  });

  it('writes legacy migration fixtures', async () => {
    if (zone !== 'UTC') return;
    jest.useFakeTimers().setSystemTime(LEGACY_NOW);
    const cases: Record<string, unknown> = {};
    for (const [name, blob] of Object.entries(legacyBlobs)) {
      kv.set('aurora/state', JSON.stringify(blob));
      await useStore.persist.rehydrate();
      cases[name] = { raw: JSON.stringify(blob), state: useStore.persist.getOptions().partialize!(useStore.getState()) };
    }
    jest.useRealTimers();
    writeFileSync(join(out!, 'legacy.json'), JSON.stringify({ now: LEGACY_NOW, cases }));
  });
});
