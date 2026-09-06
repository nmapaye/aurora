import {
  createBackup,
  parseBackup,
  localRecordCounts,
  deletionPatch,
} from '~/features/ownership/backup';
import { useStore } from '~/state/store';
test('backup round trips personal data and excludes sample records and permission grants', () => {
  const state = {
    ...useStore.getState(),
    doses: [
      { id: 'personal', timestamp: 1700000000000, mg: 95 },
      { id: 'demo:x', timestamp: 1700000000000, mg: 30 },
    ],
  };
  const backup = createBackup(state, 1700000000000);
  expect(JSON.stringify(backup)).not.toContain('permissionStatus');
  const restored = parseBackup(JSON.stringify(backup));
  expect(restored.data.doses).toEqual([state.doses[0]]);
  expect(localRecordCounts(restored.data).caffeine).toBe(1);
});
test('malformed nested imports reject entirely', () => {
  const backup = createBackup(useStore.getState(), 1700000000000);
  backup.data.planning.thresholdMg = -1;
  expect(() => parseBackup(JSON.stringify(backup))).toThrow();
});
test('sleep deletion removes imported local records and cancels timer without removing doses', () => {
  const state = useStore.getState();
  const patch = deletionPatch(state, ['sleep']);
  expect(patch.sleeps).toEqual([]);
  expect(patch.sleepRoutines?.timer).toBeNull();
  expect(patch.doses).toBeUndefined();
});
