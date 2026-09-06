import { useEffect, useSyncExternalStore } from 'react';
import { AppState, Linking } from 'react-native';
import { useStore } from '~/state/store';
import useNow from './useNow';
import { buildNativeSnapshot } from '~/features/native/model';
import {
  publishNativeSnapshot,
  syncNativeNap,
  pendingNativeRequests,
  acknowledgeNativeRequest,
  clearNativeRequests,
} from '~/services/platform/native';
import {
  enqueueNativeURL,
  pendingNativeAction,
  subscribeNativeActions,
  consumeNativeAction,
  clearNativeActions,
} from '~/features/native/actions';
import { navigate } from '~/navigation';
export default function useNativeAccess(
  ready: boolean,
  navigationReady: boolean,
) {
  const state = useStore(),
    now = useNow();
  const action = useSyncExternalStore(
    subscribeNativeActions,
    pendingNativeAction,
  );
  useEffect(() => {
    let active = true;
    Linking.getInitialURL()
      .then((url) => {
        if (active && url) enqueueNativeURL(url);
      })
      .catch(() => undefined);
    const subscription = Linking.addEventListener('url', ({ url }) =>
      enqueueNativeURL(url),
    );
    const drain = () => {
      if (AppState.currentState === 'active') {
        try {
          pendingNativeRequests().forEach(({ id, url }) => {
            if (enqueueNativeURL(url, id)) acknowledgeNativeRequest(id);
          });
        } catch {}
      }
    };
    drain();
    const interval = setInterval(drain, 1000);
    const foreground = AppState.addEventListener('change', (value) => {
      if (value === 'active') drain();
    });
    return () => {
      active = false;
      subscription.remove();
      foreground.remove();
      clearInterval(interval);
    };
  }, []);
  useEffect(() => {
    if (!ready) return;
    try {
      publishNativeSnapshot(
        state.onboarding.completed ? buildNativeSnapshot(state, now) : null,
      );
    } catch {}
    const timer = state.sleepRoutines.timer;
    const start =
      state.onboarding.completed && timer && !timer.end ? timer.start : null;
    if (AppState.currentState === 'active' || start === null)
      void syncNativeNap(start).catch(() => undefined);
  }, [ready, state, now]);
  useEffect(() => {
    const unsubscribe = useStore.subscribe((next, previous) => {
      if (previous.onboarding.completed && !next.onboarding.completed) {
        try {
          clearNativeActions();
        } catch {}
        try {
          clearNativeRequests();
        } catch {}
        try {
          publishNativeSnapshot(null);
        } catch {}
        void syncNativeNap(null).catch(() => undefined);
      }
    });
    return unsubscribe;
  }, []);
  useEffect(() => {
    if (
      !ready ||
      !navigationReady ||
      !state.onboarding.completed ||
      !state.onboarding.appWalkthroughCompleted ||
      !action
    )
      return;
    if (action.kind === 'log') navigate('NativeConfirm');
    else {
      navigate(action.kind === 'nap' ? 'SleepRoutines' : 'Summary');
      consumeNativeAction();
    }
  }, [
    ready,
    navigationReady,
    state.onboarding.completed,
    state.onboarding.appWalkthroughCompleted,
    action,
  ]);
}
