// Lightweight perf instrumentation for React Native / Expo.
// No external deps. Safe on Hermes/JSC.

type Mark = { name: string; t: number };
type Measure = { name: string; duration: number; start: number; end: number };
type Reporter = (payload: {
  marks: Mark[];
  measures: Measure[];
  frames?: { fps: number; frameMs: number; ts: number };
}) => void;

const marks: Mark[] = [];
const measures: Measure[] = [];
let reporter: Reporter | null = null;

// Monotonic clock when available; falls back gracefully.
const now = (): number => {
  // performance.now() is monotonic in Hermes / RN 0.79+
  const p: any = globalThis && (globalThis as any).performance;
  if (p && typeof p.now === 'function') return p.now();
  return Date.now();
};

/** Place a named timestamp mark. */
export function mark(name: string): number {
  const t = now();
  marks.push({ name, t });
  if (__DEV__) {
    console.log('[perf:mark]', name, t.toFixed(2));
  }
  return t;
}

/**
 * Measure duration between two marks (by name). Uses the latest pair.
 * If end mark doesn't exist yet, it will be created now.
 */
export function measure(name: string, startMark: string, endMark: string): Measure | null {
  const end = getLastMark(endMark)?.t ?? mark(endMark);
  const start = getLastMark(startMark)?.t;
  if (start == null) return null;
  const m: Measure = { name, duration: end - start, start, end };
  measures.push(m);
  if (__DEV__) {
    console.log('[perf:measure]', name, `${m.duration.toFixed(2)}ms`);
  }
  flush({ marks: [], measures: [m] });
  return m;
}

/** Wrap a synchronous function and record its duration. */
export function withTiming<T>(name: string, fn: () => T): T {
  const s = now();
  try {
    return fn();
  } finally {
    const e = now();
    const m: Measure = { name, duration: e - s, start: s, end: e };
    measures.push(m);
    if (__DEV__) {
      console.log('[perf:withTiming]', name, `${m.duration.toFixed(2)}ms`);
    }
    flush({ marks: [], measures: [m] });
  }
}

/** Wrap a promise-returning function and record its duration. */
export async function withTimingAsync<T>(name: string, fn: () => Promise<T>): Promise<T> {
  const s = now();
  try {
    return await fn();
  } finally {
    const e = now();
    const m: Measure = { name, duration: e - s, start: s, end: e };
    measures.push(m);
    if (__DEV__) {
      console.log('[perf:withTimingAsync]', name, `${m.duration.toFixed(2)}ms`);
    }
    flush({ marks: [], measures: [m] });
  }
}

/** Create a manual section timer: const end = section('boot'); ...; end(); */
export function section(name: string): () => Measure {
  const s = now();
  return () => {
    const e = now();
    const m: Measure = { name, duration: e - s, start: s, end: e };
    measures.push(m);
    flush({ marks: [], measures: [m] });
    return m;
  };
}

export function getMarks(): Mark[] {
  return marks.slice();
}
export function getMeasures(): Measure[] {
  return measures.slice();
}
export function clear(): void {
  marks.length = 0;
  measures.length = 0;
}

export function setReporter(r: Reporter | null): void {
  reporter = r;
}

function getLastMark(name: string): Mark | undefined {
  for (let i = marks.length - 1; i >= 0; i--) {
    if (marks[i].name === name) return marks[i];
  }
  return undefined;
}

function flush(delta: { marks: Mark[]; measures: Measure[]; frames?: { fps: number; frameMs: number; ts: number } }) {
  if (reporter) reporter(delta);
}

// ---- Optional frame monitor (off by default) ----
let rafId: number | null = null;
let lastTs: number | null = null;

/** Start a requestAnimationFrame monitor that reports FPS and frame time. */
export function startFrameMonitor(): void {
  if (rafId != null) return;
  const tick = (ts: number) => {
    if (lastTs != null) {
      const frameMs = ts - lastTs;
      const fps = frameMs > 0 ? 1000 / frameMs : 0;
      flush({ marks: [], measures: [], frames: { fps, frameMs, ts } });
    }
    lastTs = ts;
    rafId = (globalThis as any).requestAnimationFrame?.(tick) ?? null;
  };
  rafId = (globalThis as any).requestAnimationFrame?.(tick) ?? null;
}

/** Stop the frame monitor. */
export function stopFrameMonitor(): void {
  const g: any = globalThis as any;
  if (rafId != null && typeof g.cancelAnimationFrame === 'function') {
    g.cancelAnimationFrame(rafId);
  }
  rafId = null;
  lastTs = null;
}

// Example: attach a console reporter in dev only (opt-in).
if (__DEV__) {
  // setReporter((p) => {
  //   if (p.measures.length) {
  //     for (const m of p.measures) console.log(`[perf] ${m.name}: ${m.duration.toFixed(2)}ms`);
  //   }
  //   if (p.frames) console.log(`[fps] ${p.frames.fps.toFixed(1)} (${p.frames.frameMs.toFixed(2)}ms)`);
  // });
}