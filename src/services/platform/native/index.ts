import { requireOptionalNativeModule } from 'expo-modules-core';
import type { NativeSnapshot } from '~/features/native/model';
type Bridge = {
  pendingRequests(): { id: string; url: string }[];
  acknowledgeRequest(id: string): void;
  clearRequests(): void;
  availability(): {
    widgets: boolean;
    shortcuts: boolean;
    liveActivities: boolean;
  };
  writeSnapshot(json: string | null): void;
  syncNap(start: number | null): Promise<boolean>;
};
const bridge = requireOptionalNativeModule<Bridge>('AuroraNative');
export const nativeAvailability = () =>
  bridge?.availability() ?? {
    widgets: false,
    shortcuts: false,
    liveActivities: false,
  };
let lastPublished: string | null | undefined;
export function publishNativeSnapshot(snapshot: NativeSnapshot | null) {
  const json = snapshot ? JSON.stringify(snapshot) : null;
  if (json === lastPublished) return;
  bridge?.writeSnapshot(json);
  lastPublished = json;
}
let napQueue: Promise<unknown> = Promise.resolve();
export function syncNativeNap(start: number | null) {
  const result = napQueue
    .catch(() => undefined)
    .then(() => bridge?.syncNap(start) ?? false);
  napQueue = result;
  return result;
}

export const pendingNativeRequests = () => bridge?.pendingRequests() ?? [];
export const acknowledgeNativeRequest = (id: string) =>
  bridge?.acknowledgeRequest(id);
export const clearNativeRequests = () => bridge?.clearRequests();
