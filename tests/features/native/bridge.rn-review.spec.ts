import { buildNativeSnapshot } from '~/features/native/model';
import { useStore } from '~/state/store';
const mockWrite = jest.fn();
const mockSync = jest.fn(() => Promise.resolve(true));
jest.mock('expo-modules-core', () => ({
  requireOptionalNativeModule: () => ({
    writeSnapshot: mockWrite,
    syncNap: mockSync,
  }),
}));
import {
  publishNativeSnapshot,
  syncNativeNap,
} from '~/services/platform/native';

test('deduplicates successful writes but invalidates after clear and retries failed writes', () => {
  const snapshot = buildNativeSnapshot(useStore.getState(), 1700000000000);
  publishNativeSnapshot(snapshot);
  publishNativeSnapshot(snapshot);
  expect(mockWrite).toHaveBeenCalledTimes(1);
  publishNativeSnapshot(null);
  expect(mockWrite).toHaveBeenLastCalledWith(null);
  publishNativeSnapshot(snapshot);
  expect(mockWrite).toHaveBeenCalledTimes(3);
  mockWrite.mockImplementationOnce(() => {
    throw new Error('write unavailable');
  });
  expect(() => publishNativeSnapshot(null)).toThrow();
  publishNativeSnapshot(null);
  expect(mockWrite).toHaveBeenCalledTimes(5);
  expect(mockWrite).toHaveBeenLastCalledWith(null);
});

test('serializes reset after any in-flight nap write so the final native state is ended', async () => {
  let release: ((value: boolean) => void) | undefined;
  mockSync.mockImplementationOnce(
    () =>
      new Promise<boolean>((resolve) => {
        release = resolve;
      }),
  );
  const start = syncNativeNap(1700000000000);
  await Promise.resolve();
  await Promise.resolve();
  const reset = syncNativeNap(null);
  expect(mockSync).toHaveBeenCalledTimes(1);
  release!(true);
  await start;
  await reset;
  expect(mockSync.mock.calls).toEqual([[1700000000000], [null]]);
});
