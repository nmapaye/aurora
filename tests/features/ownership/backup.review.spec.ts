import { createBackup, parseBackup, deletionPatch } from '~/features/ownership/backup';
import { defaultOwnership } from '~/features/ownership/model';
import { useStore } from '~/state/store';

const now = new Date(2026, 8, 7, 12).getTime();
function source() {
  const state = useStore.getState();
  return { ...state, ownership: defaultOwnership(), doses: [{ id: 'personal:dose', timestamp: now, mg: 95, note: 'Personal note' }], sleeps: [{ id: 'health:sleep', start: now - 12 * 3600000, end: now - 4 * 3600000, type: 'sleep' as const }] };
}
it('exports detached personal records and never serializes permission grants or sync status', () => {
  const state = source();
  state.doses.push({ ...state.doses[0], id: 'demo:dose', note: 'Sample note' });
  const backup = createBackup(state, now);
  state.doses[0].note = 'Changed after export';
  const parsed = parseBackup(JSON.stringify(backup));
  expect(parsed.data.doses).toHaveLength(1);
  expect(parsed.data.doses[0].note).toBe('Personal note');
  expect(parsed.data.sleeps[0].id).toBe('health:sleep');
  expect(parsed.data).not.toHaveProperty('healthSync');
  expect(parsed.data.onboarding).not.toHaveProperty('permissionStatus');
});
it('rejects unsupported versions, duplicate IDs, and invalid numeric timestamps atomically', () => {
  const state = source(), before = JSON.stringify(state.doses);
  const cases = [
    (v: any) => { v.version = 99; },
    (v: any) => { v.data.doses.push({ ...v.data.doses[0] }); },
    ...[null, true, '2026-09-07', 1e100].map(timestamp => (v: any) => { v.data.doses[0].timestamp = timestamp; }),
    (v: any) => { v.data.sleepRoutines.weekly[0].bedtime = 2000; },
  ];
  for (const mutate of cases) {
    const backup = createBackup(state, now);
    mutate(backup);
    expect(() => parseBackup(JSON.stringify(backup))).toThrow();
    expect(JSON.stringify(state.doses)).toBe(before);
  }
});
it('keeps active and stopped nap timers when only routines are deleted', () => {
  for (const timer of [{ start: now - 3600000 }, { start: now - 3600000, end: now - 60000 }]) {
    const state = source();
    state.sleepRoutines = { ...state.sleepRoutines, timer };
    const patch = deletionPatch(state, ['routines']);
    expect(patch.sleepRoutines?.timer).toEqual(timer);
    expect(patch.sleeps).toBeUndefined();
    expect(state.sleepRoutines.timer).toEqual(timer);
  }
});
it('clears sleep copies and journals without touching intake, then clears all transient state for all-data deletion', () => {
  const state = source();
  state.sleepRoutines = { ...state.sleepRoutines, annotations: { 'health:sleep': { quality: 4, note: 'Journal' } }, timer: { start: now - 60000 } };
  const sleep = deletionPatch(state, ['sleep']);
  expect(sleep.sleeps).toEqual([]);
  expect(sleep.sleepRoutines?.annotations).toEqual({});
  expect(sleep.sleepRoutines?.timer).toBeNull();
  expect(sleep.doses).toBeUndefined();
  const all = deletionPatch(state, ['all']);
  expect(all.doses).toEqual([]);
  expect(all.sleeps).toEqual([]);
  expect(all.doseUndo).toBeNull();
  expect(all.prefs?.notifyCutoff).toBe(false);
  expect(all.sleepRoutines?.timer).toBeNull();
  expect(all.onboarding?.completed).toBe(false);
});
