import {
  describeHealthAccess,
  describeSetupNextAction,
  formatSleepTarget,
  getOnboardingLayoutMode,
  getOnboardingStepCopy,
  getSetupStepState,
} from '~/features/onboarding/presentation';

describe('onboarding presentation', () => {
  it('uses two columns on iPad portrait and one centered column elsewhere', () => {
    expect(getOnboardingLayoutMode({ width: 1032, fontScale: 1 })).toBe('split');
    expect(getOnboardingLayoutMode({ width: 834, fontScale: 1 })).toBe('split');
    // iPad mini portrait, Split View, and iPhone.
    expect(getOnboardingLayoutMode({ width: 744, fontScale: 1 })).toBe('stacked');
    expect(getOnboardingLayoutMode({ width: 507, fontScale: 1 })).toBe('stacked');
    expect(getOnboardingLayoutMode({ width: 393, fontScale: 1 })).toBe('stacked');
  });

  it('falls back to one column at accessibility text sizes', () => {
    expect(getOnboardingLayoutMode({ width: 1032, fontScale: 1.35 })).toBe('split');
    expect(getOnboardingLayoutMode({ width: 1032, fontScale: 1.6 })).toBe('stacked');
  });

  it('never describes Health access as granted', () => {
    expect(describeHealthAccess('healthkit', 'idle')).toBe('Not requested yet');
    expect(describeHealthAccess('healthkit', 'granted')).toBe('Requested, read-only');
    expect(describeHealthAccess('healthkit', 'denied')).toBe('Request incomplete');
    expect(describeHealthAccess('manual', 'unsupported')).toBe('Not used');
    for (const status of ['idle', 'granted', 'denied', 'unsupported'] as const) {
      expect(describeHealthAccess('healthkit', status)).not.toMatch(/granted|connected/i);
    }
  });

  it('keeps manual and denied paths finishable without Health', () => {
    const base = { importStatus: 'idle' as const, importedCount: 0 };
    expect(
      describeSetupNextAction({ ...base, source: 'manual', permissionStatus: 'unsupported' }),
    ).toMatch(/manually/);
    expect(
      describeSetupNextAction({ ...base, source: 'healthkit', permissionStatus: 'denied' }),
    ).toBe('Connect Health, or finish with manual setup.');
    expect(getOnboardingStepCopy(2, 'manual').title).toBe('Ready for manual logging');
    expect(getOnboardingStepCopy(2, 'healthkit').title).toBe('Read-only access to Health');
  });

  it('formats half-hour targets and step states', () => {
    expect(formatSleepTarget(8).spoken).toBe('8 hours');
    expect(formatSleepTarget(7.5).value).toBe('7.5');
    expect([0, 1, 2].map((index) => getSetupStepState(index, 1))).toEqual([
      'done',
      'current',
      'upcoming',
    ]);
  });
});
