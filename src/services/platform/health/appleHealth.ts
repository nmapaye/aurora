import { requireNativeModule } from 'expo-modules-core';

type SleepSample = { start: number; end: number; value?: number; label?: string };

let Native: any = null;
try {
  Native = requireNativeModule('HealthBridge');
} catch {
  Native = null;
}

export async function isAvailable(): Promise<boolean> {
  try { return (await Native?.isAvailable?.()) ?? false; } catch { return false; }
}

export async function requestAuthorization(): Promise<boolean> {
  try { return (await Native?.requestAuthorization?.()) ?? false; } catch { return false; }
}

export async function getSleepSamples(startMs: number, endMs: number): Promise<SleepSample[]> {
  try { return (await Native?.getSleepSamples?.(startMs, endMs)) ?? []; } catch { return []; }
}

export default { isAvailable, requestAuthorization, getSleepSamples };
