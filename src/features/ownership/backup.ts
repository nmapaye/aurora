import type { State, PersistedState } from '~/state/store';
import { defaultOwnership, normalizeOwnership } from './model';
import {
  defaultPlanningState,
  normalizePlanning,
} from '~/features/planning/model';
import {
  defaultSleepRoutines,
  normalizeSleepRoutines,
} from '~/features/sleep/upgrades';
import {
  defaultCaffeineState,
  normalizeCaffeine,
} from '~/features/caffeine/upgrades';
import { DEFAULT_HALFLIFE_H, DEFAULT_TARGET_SLEEP_H } from '~/domain/constants';
export type BackupData = Omit<
  PersistedState,
  'healthSync' | 'demoMode' | 'onboarding'
> & { onboarding: Omit<PersistedState['onboarding'], 'permissionStatus'> };
export type Backup = {
  format: 'aurora-backup';
  version: 1;
  createdAt: number;
  data: BackupData;
};
export const LOCAL_CATEGORIES = [
  'caffeine',
  'sleep',
  'vigilance',
  'checkIns',
  'plans',
  'drinks',
  'routines',
  'all',
] as const;
export type LocalCategory = (typeof LOCAL_CATEGORIES)[number];
const personal = <T extends { id: string }>(rows: T[]) =>
  rows.filter((x) => !x.id.startsWith('demo:'));
export function createBackup(
  state: Pick<State, keyof PersistedState>,
  now: number,
): Backup {
  const { permissionStatus: _permission, ...onboarding } = state.onboarding;
  const data: BackupData = {
    doses: personal(state.doses),
    sleeps: personal(state.sleeps),
    vigilanceSessions: personal(state.vigilanceSessions),
    caffeine: { ...state.caffeine, drinks: personal(state.caffeine.drinks) },
    sleepRoutines: {
      ...state.sleepRoutines,
      annotations: Object.fromEntries(
        Object.entries(state.sleepRoutines.annotations).filter(
          ([id]) => !id.startsWith('demo:'),
        ),
      ),
    },
    planning: {
      ...state.planning,
      checkIns: personal(state.planning.checkIns),
    },
    prefs: { ...state.prefs },
    onboarding,
    appearanceMode: state.appearanceMode,
    ownership: state.ownership,
  };
  return JSON.parse(
    JSON.stringify({
      format: 'aurora-backup',
      version: 1,
      createdAt: now,
      data,
    }),
  );
}
const isRecord = (v: unknown): v is Record<string, any> =>
  !!v && typeof v === 'object' && !Array.isArray(v);
const finite = (v: unknown, min = 0, max = 8640000000000000) =>
  typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;
const text = (v: unknown) => typeof v === 'string';
function same(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (Array.isArray(a) && Array.isArray(b))
    return a.length === b.length && a.every((v, i) => same(v, b[i]));
  if (isRecord(a) && isRecord(b)) {
    const ak = Object.keys(a),
      bk = Object.keys(b);
    return (
      ak.length === bk.length &&
      ak.every((k) => Object.hasOwn(b, k) && same(a[k], b[k]))
    );
  }
  return false;
}
function rows(
  value: unknown,
  valid: (v: Record<string, any>) => boolean,
): boolean {
  return (
    Array.isArray(value) &&
    value.length <= 100000 &&
    value.every(
      (x) =>
        isRecord(x) &&
        text(x.id) &&
        x.id.length > 0 &&
        !x.id.startsWith('demo:') &&
        valid(x),
    ) &&
    new Set(value.map((x) => x.id)).size === value.length
  );
}
function keys(v: Record<string, any>, allowed: string[]) {
  return Object.keys(v).every((k) => allowed.includes(k));
}
export function parseBackup(json: string): Backup {
  if (json.length > 20_000_000) throw new Error('Backup exceeds 20 MB.');
  let v: any;
  try {
    v = JSON.parse(json);
  } catch {
    throw new Error('This file is not valid JSON.');
  }
  const bad = () => {
    throw new Error(
      'This is not a valid Aurora version 1 backup. No data was changed.',
    );
  };
  if (
    !isRecord(v) ||
    v.format !== 'aurora-backup' ||
    v.version !== 1 ||
    !finite(v.createdAt) ||
    !isRecord(v.data) ||
    !keys(v, ['format', 'version', 'createdAt', 'data'])
  )
    return bad();
  const d = v.data;
  if (
    !keys(d, [
      'doses',
      'sleeps',
      'vigilanceSessions',
      'caffeine',
      'sleepRoutines',
      'planning',
      'prefs',
      'onboarding',
      'appearanceMode',
      'ownership',
    ])
  )
    return bad();
  if (
    !rows(
      d.doses,
      (x) =>
        finite(x.timestamp) &&
        finite(x.mg, 0, 2000) &&
        (x.source === undefined || text(x.source)) &&
        (x.note === undefined || text(x.note)) &&
        keys(x, ['id', 'timestamp', 'mg', 'source', 'note']),
    )
  )
    return bad();
  if (
    !rows(
      d.sleeps,
      (x) =>
        finite(x.start) &&
        finite(x.end) &&
        x.end > x.start &&
        ['sleep', 'nap'].includes(x.type) &&
        (x.note === undefined || text(x.note)) &&
        keys(x, ['id', 'start', 'end', 'type', 'note']),
    )
  )
    return bad();
  if (
    !rows(
      d.vigilanceSessions,
      (x) =>
        finite(x.startedAt) &&
        finite(x.completedAt) &&
        x.completedAt >= x.startedAt &&
        finite(x.durationMs) &&
        [
          'trialCount',
          'validReactionCount',
          'falseStartCount',
          'lapseCount',
        ].every((k) => finite(x[k]) && Number.isInteger(x[k])) &&
        [
          'medianReactionMs',
          'meanReactionMs',
          'fastestReactionMs',
          'reactionStdDevMs',
        ].every((k) => x[k] === null || finite(x[k])) &&
        finite(x.score, 0, 100) &&
        ['Sharp', 'Steady', 'Slipping', 'Fatigued'].includes(x.rating) &&
        keys(x, [
          'id',
          'startedAt',
          'completedAt',
          'durationMs',
          'trialCount',
          'validReactionCount',
          'falseStartCount',
          'lapseCount',
          'medianReactionMs',
          'meanReactionMs',
          'fastestReactionMs',
          'reactionStdDevMs',
          'score',
          'rating',
        ]),
    )
  )
    return bad();
  for (const x of d.vigilanceSessions) {
    if (
      x.validReactionCount + x.lapseCount !== x.trialCount ||
      x.durationMs !== x.completedAt - x.startedAt ||
      [
        'medianReactionMs',
        'meanReactionMs',
        'fastestReactionMs',
        'reactionStdDevMs',
      ].some((k) => (x[k] === null) !== (x.validReactionCount === 0))
    )
      return bad();
  }
  const p = d.prefs,
    o = d.onboarding;
  if (
    !isRecord(p) ||
    !finite(p.halfLife, 0.5, 16) ||
    !finite(p.targetSleep, 1, 24) ||
    !finite(p.dailyLimitMg, 0, 2000) ||
    !finite(p.cutoffHour, 0, 23) ||
    !Number.isInteger(p.cutoffHour) ||
    typeof p.notifyCutoff !== 'boolean' ||
    (p.tz !== undefined && !text(p.tz)) ||
    !keys(p, [
      'halfLife',
      'targetSleep',
      'dailyLimitMg',
      'cutoffHour',
      'notifyCutoff',
      'tz',
    ])
  )
    return bad();
  try {
    if (p.tz !== undefined)
      new Intl.DateTimeFormat(undefined, { timeZone: p.tz }).format(
        new Date(0),
      );
  } catch {
    return bad();
  }
  if (
    !isRecord(o) ||
    typeof o.completed !== 'boolean' ||
    !['manual', 'healthkit'].includes(o.source) ||
    typeof o.appWalkthroughCompleted !== 'boolean' ||
    !finite(o.appWalkthroughStep, 0, 9) ||
    !Number.isInteger(o.appWalkthroughStep) ||
    (o.completedAt !== undefined && !finite(o.completedAt)) ||
    !keys(o, [
      'completed',
      'source',
      'completedAt',
      'appWalkthroughCompleted',
      'appWalkthroughStep',
    ])
  )
    return bad();
  if (!['system', 'light', 'dark'].includes(d.appearanceMode)) return bad();
  try {
    if (
      !same(d.planning, normalizePlanning(d.planning)) ||
      !same(d.caffeine, normalizeCaffeine(d.caffeine)) ||
      !same(
        d.sleepRoutines,
        normalizeSleepRoutines(d.sleepRoutines, p.targetSleep),
      ) ||
      !same(
        {
          ...d.ownership,
          native: d.ownership?.native ?? { showLockValues: false },
        },
        normalizeOwnership(d.ownership),
      )
    )
      return bad();
  } catch {
    return bad();
  }
  if (
    d.planning.checkIns.some((x: any) => x.id.startsWith('demo:')) ||
    Object.keys(d.sleepRoutines.annotations).some((x) => x.startsWith('demo:'))
  )
    return bad();
  v.data.ownership = normalizeOwnership(v.data.ownership);
  return v as Backup;
}
export function localRecordCounts(
  s: Pick<
    BackupData,
    | 'doses'
    | 'sleeps'
    | 'vigilanceSessions'
    | 'caffeine'
    | 'planning'
    | 'sleepRoutines'
  >,
) {
  return {
    caffeine:
      s.doses.length + s.caffeine.zeroDays.length + (s.caffeine.draft ? 1 : 0),
    sleep:
      s.sleeps.length +
      Object.keys(s.sleepRoutines.annotations).length +
      (s.sleepRoutines.timer ? 1 : 0),
    vigilance: s.vigilanceSessions.length,
    checkIns: s.planning.checkIns.length,
    plans:
      s.planning.scenarios.length +
      s.planning.experiments.length +
      s.planning.budget.allocations.length +
      (s.planning.reduction ? 1 : 0),
    drinks: s.caffeine.drinks.length,
    routines: Object.keys(s.sleepRoutines.exceptions).length + 7,
  };
}
export function deletionPatch(
  s: State,
  categories: LocalCategory[],
): Partial<State> {
  if (categories.includes('all'))
    return {
      doses: [],
      sleeps: [],
      vigilanceSessions: [],
      caffeine: normalizeCaffeine(defaultCaffeineState),
      planning: defaultPlanningState(),
      sleepRoutines: defaultSleepRoutines(DEFAULT_TARGET_SLEEP_H),
      ownership: defaultOwnership(),
      prefs: {
        halfLife: DEFAULT_HALFLIFE_H,
        targetSleep: DEFAULT_TARGET_SLEEP_H,
        dailyLimitMg: 400,
        cutoffHour: 16,
        notifyCutoff: false,
      },
      onboarding: {
        completed: false,
        source: 'healthkit',
        permissionStatus: 'idle',
        appWalkthroughCompleted: false,
        appWalkthroughStep: 0,
      },
      healthSync: { importedCount: 0, importStatus: 'idle' },
      demoMode: false,
      appearanceMode: 'system',
      doseUndo: null,
    };
  const patch: Partial<State> = {};
  let caffeine = { ...s.caffeine },
    planning = { ...s.planning },
    routines = { ...s.sleepRoutines };
  if (categories.includes('caffeine')) {
    patch.doses = [];
    patch.doseUndo = null;
    caffeine = { ...caffeine, draft: null, zeroDays: [] };
  }
  if (categories.includes('sleep')) {
    patch.sleeps = [];
    routines = { ...routines, annotations: {}, timer: null };
    patch.healthSync = { importedCount: 0, importStatus: 'idle' };
  }
  if (categories.includes('vigilance')) patch.vigilanceSessions = [];
  if (categories.includes('checkIns')) planning = { ...planning, checkIns: [] };
  if (categories.includes('plans'))
    planning = { ...defaultPlanningState(), checkIns: planning.checkIns };
  if (categories.includes('drinks'))
    caffeine = {
      ...caffeine,
      drinks: [],
      favoriteIds: [...defaultCaffeineState.favoriteIds],
    };
  if (categories.includes('routines')) {
    routines = {
      ...defaultSleepRoutines(s.prefs.targetSleep),
      annotations: routines.annotations,
      timer: routines.timer,
    };
    patch.ownership = {
      ...s.ownership,
      reminders: defaultOwnership().reminders,
    };
    patch.prefs = { ...s.prefs, notifyCutoff: false };
  }
  if (caffeine !== s.caffeine) patch.caffeine = caffeine;
  if (planning !== s.planning) patch.planning = planning;
  if (routines !== s.sleepRoutines) patch.sleepRoutines = routines;
  return patch;
}
