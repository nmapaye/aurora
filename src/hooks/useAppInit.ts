// src/hooks/useAppInit.ts
import { useEffect, useState } from 'react';

/**
 * Boot gate without hard dependency on named exports from the store.
 * - Dynamically imports the store module.
 * - If persist is configured, calls store.persist.rehydrate().
 * - If an exported enablePersistence() exists, invokes it; otherwise no-op.
 */
export function useAppInit() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const storeMod: any = await import('~/state/store');
        const maybeRehydrate = storeMod?.rehydrate
          ? storeMod.rehydrate()
          : storeMod?.useStore?.persist?.rehydrate?.()
            ? storeMod.useStore.persist.rehydrate()
            : Promise.resolve();
        await maybeRehydrate;

        if (typeof storeMod?.enablePersistence === 'function') {
          await Promise.resolve(storeMod.enablePersistence());
        }
      } catch (e) {
        console.error('[init]', e);
      } finally {
        if (alive) setReady(true);
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  return ready;
}
