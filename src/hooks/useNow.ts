import { useSyncExternalStore } from 'react';
import { AppState } from 'react-native';
import type { AppStateStatus, NativeEventSubscription } from 'react-native';

import { useStore } from '~/state/store';

// Modeled values (active caffeine, estimated alertness) drift with the clock
// even when stored data does not. Every consumer shares one clock: it ticks
// once a minute while the app is active, pauses in the background, and
// catches up as soon as the app returns to the foreground. Consumers re-render
// together on each tick rather than each running its own timer.
export const NOW_TICK_MS = 60_000;

let current = Date.now();
let timer: ReturnType<typeof setInterval> | null = null;
let appStateSubscription: NativeEventSubscription | null = null;
let recordsSubscription: (() => void) | null = null;
const listeners = new Set<() => void>();

function tick() {
  current = Date.now();
  listeners.forEach((listener) => listener());
}

function stopTimer() {
  if (timer === null) return;
  clearInterval(timer);
  timer = null;
}

function startTimer() {
  stopTimer();
  timer = setInterval(tick, NOW_TICK_MS);
}

function onAppStateChange(state: AppStateStatus) {
  if (state === 'active') {
    tick();
    startTimer();
  } else {
    stopTimer();
  }
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  if (listeners.size === 1) {
    appStateSubscription = AppState.addEventListener(
      'change',
      onAppStateChange,
    );
    if (AppState.currentState !== 'background') startTimer();
    // A record saved "now" must never sit ahead of the shared clock, or
    // every recorded-so-far filter (timestamp <= now) would hide it until the
    // next minute tick. Re-read the clock whenever recorded data changes.
    recordsSubscription = useStore.subscribe((state, previous) => {
      if (
        state.doses !== previous.doses ||
        state.sleeps !== previous.sleeps ||
        state.vigilanceSessions !== previous.vigilanceSessions
      ) {
        tick();
      }
    });
  }
  return () => {
    listeners.delete(listener);
    if (listeners.size > 0) return;
    stopTimer();
    appStateSubscription?.remove();
    appStateSubscription = null;
    recordsSubscription?.();
    recordsSubscription = null;
  };
}

function getSnapshot() {
  // With no subscribers nothing keeps `current` fresh, so the first reader
  // after an idle period refreshes it. Within a tick the value is stable.
  if (listeners.size === 0 && Math.abs(Date.now() - current) >= NOW_TICK_MS) {
    current = Date.now();
  }
  return current;
}

export default function useNow() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}
