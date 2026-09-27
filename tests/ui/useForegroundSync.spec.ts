import * as healthImport from '~/features/sleep/healthImport';
import * as notifications from '~/services/platform/notifications';
import {
  HEALTH_REFRESH_INTERVAL_MS,
  runForegroundSync,
  shouldRefreshHealth,
} from '~/hooks/useForegroundSync';
import { useStore } from '~/state/store';

const NOW = 1_800_000_000_000;

function setConnected(overrides: { lastSyncedAt?: number; demoMode?: boolean } = {}) {
  const state = useStore.getState();
  useStore.setState({
    demoMode: overrides.demoMode ?? false,
    onboarding: { ...state.onboarding, completed: true, permissionStatus: 'granted' },
    healthSync: { importedCount: 0, importStatus: 'succeeded', lastSyncedAt: overrides.lastSyncedAt },
    prefs: { ...state.prefs, notifyCutoff: true, cutoffHour: 15 },
  });
}

beforeEach(() => {
  jest.spyOn(notifications, 'syncCutoffReminder').mockResolvedValue(true);
  jest.spyOn(healthImport, 'importHealthSleep').mockResolvedValue({ ok: true, nights: 0 });
});
afterEach(() => jest.restoreAllMocks());

describe('shouldRefreshHealth', () => {
  it('refreshes a connected account once the interval has passed', () => {
    setConnected({ lastSyncedAt: NOW - HEALTH_REFRESH_INTERVAL_MS });
    expect(shouldRefreshHealth(NOW)).toBe(true);
  });

  it('skips recent syncs, sample data, and accounts without Health access', () => {
    setConnected({ lastSyncedAt: NOW - 60_000 });
    expect(shouldRefreshHealth(NOW)).toBe(false);

    setConnected({ demoMode: true });
    expect(shouldRefreshHealth(NOW)).toBe(false);

    setConnected();
    useStore.setState({ onboarding: { ...useStore.getState().onboarding, permissionStatus: 'denied' } });
    expect(shouldRefreshHealth(NOW)).toBe(false);
  });
});

describe('runForegroundSync', () => {
  it('reconciles the reminder without prompting and refreshes stale Health data', async () => {
    setConnected({ lastSyncedAt: NOW - 2 * HEALTH_REFRESH_INTERVAL_MS });

    await runForegroundSync(NOW);

    expect(notifications.syncCutoffReminder).toHaveBeenCalledWith(true, 15, { prompt: false });
    expect(healthImport.importHealthSleep).toHaveBeenCalledWith({ days: 30, now: NOW });
  });

  it('does nothing before onboarding is complete', async () => {
    useStore.setState({ onboarding: { ...useStore.getState().onboarding, completed: false } });

    await runForegroundSync(NOW);

    expect(notifications.syncCutoffReminder).not.toHaveBeenCalled();
    expect(healthImport.importHealthSleep).not.toHaveBeenCalled();
  });
});
