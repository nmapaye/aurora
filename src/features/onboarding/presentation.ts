import type {
  HealthImportStatus,
  HealthPermissionStatus,
  OnboardingSource,
} from '~/state/store';

// Pure copy and layout decisions for first-run setup. The screen renders these
// without deciding wording, so the honest-state rules stay testable.

export const ONBOARDING_STEP_COUNT = 3;

export const SLEEP_TARGET_RANGE = { min: 5, max: 10, step: 0.5 } as const;
export const SLEEP_TARGET_PRESETS = [7, 8, 9] as const;

export type OnboardingLayoutMode = 'stacked' | 'split';

// Two columns need room for both the setup summary and the form. Narrow iPad
// windows and accessibility text sizes fall back to one centered column.
export const SPLIT_LAYOUT_MIN_WIDTH = 800;
export const SPLIT_LAYOUT_MAX_FONT_SCALE = 1.35;

export function getOnboardingLayoutMode({
  width,
  fontScale,
}: {
  width: number;
  fontScale: number;
}): OnboardingLayoutMode {
  return width >= SPLIT_LAYOUT_MIN_WIDTH &&
    fontScale <= SPLIT_LAYOUT_MAX_FONT_SCALE
    ? 'split'
    : 'stacked';
}

export type OnboardingStepCopy = {
  eyebrow: string;
  title: string;
  body: string;
  summaryLabel: string;
};

export function getOnboardingStepCopy(
  step: number,
  source: OnboardingSource,
): OnboardingStepCopy {
  if (step === 0) {
    return {
      eyebrow: 'Your nights',
      title: 'How much sleep do you aim for?',
      body: 'Aurora compares your sleep with this nightly target. You can change it anytime in Settings.',
      summaryLabel: 'Sleep target',
    };
  }
  if (step === 1) {
    return {
      eyebrow: 'Your sleep record',
      title: 'Where should sleep come from?',
      body: 'Read recent nights from Apple Health, or log them yourself.',
      summaryLabel: 'Sleep source',
    };
  }
  return source === 'manual'
    ? {
        eyebrow: 'Access',
        title: 'Ready for manual logging',
        body: 'Aurora will not ask for Health access. You can connect Health later from Sleep.',
        summaryLabel: 'Health access',
      }
    : {
        eyebrow: 'Access',
        title: 'Read-only access to Health',
        body: 'Aurora asks to read sleep only. You choose what to share in the Health sheet.',
        summaryLabel: 'Health access',
      };
}

export function formatSleepTarget(hours: number) {
  const value = Number.isInteger(hours) ? String(hours) : hours.toFixed(1);
  return { value, unit: 'hours', spoken: `${value} hours` };
}

export function describeSleepSource(source: OnboardingSource) {
  return source === 'manual' ? 'Manual logging' : 'Apple Health';
}

// Never reports access as granted: HealthKit does not reveal read decisions.
export function describeHealthAccess(
  source: OnboardingSource,
  permissionStatus: HealthPermissionStatus,
) {
  if (source === 'manual') return 'Not used';
  switch (permissionStatus) {
    case 'granted':
      return 'Requested, read-only';
    case 'denied':
      return 'Request incomplete';
    case 'unsupported':
      return 'Unavailable';
    default:
      return 'Not requested yet';
  }
}

export type SetupStepState = 'done' | 'current' | 'upcoming';

export function getSetupStepState(index: number, step: number): SetupStepState {
  if (index < step) return 'done';
  return index === step ? 'current' : 'upcoming';
}

export function describeSetupNextAction({
  source,
  permissionStatus,
  importStatus,
  importedCount,
}: {
  source: OnboardingSource;
  permissionStatus: HealthPermissionStatus;
  importStatus: HealthImportStatus;
  importedCount: number;
}) {
  if (source === 'manual') {
    return 'Finish setup to log caffeine and sleep manually.';
  }
  if (permissionStatus !== 'granted') {
    return 'Connect Health, or finish with manual setup.';
  }
  switch (importStatus) {
    case 'succeeded':
      return importedCount > 0
        ? 'Finish setup, then review imported sleep.'
        : 'Finish setup to log sleep manually, or check sleep records and access in Health.';
    case 'importing':
      return 'Health request completed. Sleep import is in progress.';
    case 'failed':
      return 'Health request completed. Sleep import needs a retry.';
    default:
      return 'Health request completed. Recent sleep has not been imported yet.';
  }
}
