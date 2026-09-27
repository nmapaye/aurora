import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import { Share } from 'react-native';

import SettingsScreen from '~/screens/SettingsScreen';
import { syncCutoffReminder } from '~/services/platform/notifications';
import { useStore } from '~/state/store';

jest.mock('~/services/platform/notifications', () => ({ syncCutoffReminder: jest.fn() }));
jest.mock('~/navigation', () => ({ goBack: jest.fn() }));
jest.mock('@expo/vector-icons', () => ({ Ionicons: () => null }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

const now = new Date(2026, 6, 24, 12, 0, 0, 0).getTime();
const at = (date: number, hour: number) => new Date(2026, 6, date, hour, 0, 0, 0).getTime();

function sharedMessage() {
  return jest.mocked(Share.share).mock.calls[0]?.[0].message ?? '';
}

describe('Settings → Data export', () => {
  beforeEach(() => {
    jest.mocked(syncCutoffReminder).mockResolvedValue(true);
    jest.spyOn(Date, 'now').mockReturnValue(now);
    jest.spyOn(Share, 'share').mockResolvedValue({ action: 'sharedAction' });
    useStore.setState({
      doses: [
        { id: 'dose:a', timestamp: at(22, 9), mg: 95, source: 'Drip' },
        { id: 'demo:dose:1', timestamp: at(24, 8), mg: 60, source: 'Tea', note: 'Sample data' },
      ],
      vigilanceSessions: [],
    });
  });

  afterEach(() => jest.restoreAllMocks());

  it('exports every recorded caffeine entry with its data source, and only recorded rows', async () => {
    await render(<SettingsScreen />);
    await fireEvent.press(screen.getByRole('button', { name: /Export Caffeine Entries/ }));

    await waitFor(() => expect(Share.share).toHaveBeenCalledTimes(1));
    const lines = sharedMessage().split('\n');
    expect(lines[0]).toBe('id,local_date,timestamp,datetime,mg,drink,note,data_source');
    expect(lines).toHaveLength(3);
    expect(lines[1]).toMatch(/^"dose:a","2026-07-22".*"95","Drip","","Manual"$/);
    expect(lines[2]).toMatch(/"Sample Data"$/);
  });

  it('exports daily totals with unlogged days marked no record, never 0 mg', async () => {
    await render(<SettingsScreen />);
    await fireEvent.press(screen.getByRole('button', { name: /Export Daily Caffeine Totals/ }));

    await waitFor(() => expect(Share.share).toHaveBeenCalledTimes(1));
    expect(sharedMessage()).toBe(
      [
        'date,mg,entries,status,data_source',
        '"2026-07-22","95","1","recorded","Manual"',
        '"2026-07-23","","0","no record",""',
        '"2026-07-24","60","1","recorded","Sample Data"',
      ].join('\n'),
    );
  });

  it('exports Reaction Tests from Settings', async () => {
    await render(<SettingsScreen />);
    await fireEvent.press(screen.getByRole('button', { name: /Export Reaction Tests/ }));

    await waitFor(() => expect(Share.share).toHaveBeenCalledTimes(1));
    expect(sharedMessage().split('\n')[0]).toMatch(/^id,started_at,.*,data_source$/);
  });

  it('shows a readable export failure', async () => {
    jest.mocked(Share.share).mockRejectedValueOnce(new Error('Sharing unavailable'));
    await render(<SettingsScreen />);
    await fireEvent.press(screen.getByRole('button', { name: /Export Daily Caffeine Totals/ }));

    expect(
      await screen.findByRole('alert', { name: 'Unable to export daily totals. Sharing unavailable' }),
    ).toBeOnTheScreen();
  });
});
