import { jsonStringStorage } from '~/services/storage';
import { parseNativeAction, type NativeAction } from './model';
// Each URL becomes a separate review. Receiving another action cannot replace
// a draft the user is currently reviewing.
type Queued = { url: string; requestId?: string; action: NativeAction };
const storageKey = 'aurora/native-actions';
function recover(): Queued[] {
  try {
    const saved: unknown = JSON.parse(
      jsonStringStorage.getItem(storageKey) ?? '[]',
    );
    if (!Array.isArray(saved)) return [];
    return saved.slice(0, 20).flatMap((item) => {
      if (!item || typeof item.url !== 'string') return [];
      const action = parseNativeAction(item.url);
      return action
        ? [
            {
              url: item.url,
              requestId:
                typeof item.requestId === 'string' ? item.requestId : undefined,
              action,
            },
          ]
        : [];
    });
  } catch {
    return [];
  }
}
const queue: Queued[] = recover();
function save(next: Queued[]) {
  jsonStringStorage.setItem(
    storageKey,
    JSON.stringify(next.map(({ url, requestId }) => ({ url, requestId }))),
  );
}
const listeners = new Set<() => void>();
export const pendingNativeAction = () => queue[0]?.action ?? null;
export function enqueueNativeURL(url: string, requestId?: string) {
  const action = parseNativeAction(url);
  if (!action) return false;
  if (requestId && queue.some((item) => item.requestId === requestId))
    return true;
  if (queue.length >= 20) return false;
  const item = { url, requestId, action };
  save([...queue, item]);
  queue.push(item);
  listeners.forEach((fn) => fn());
  return true;
}
export function consumeNativeAction() {
  save(queue.slice(1));
  queue.shift();
  listeners.forEach((fn) => fn());
}
export function clearNativeActions() {
  save([]);
  queue.length = 0;
  listeners.forEach((fn) => fn());
}
export function subscribeNativeActions(fn: () => void) {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
}
