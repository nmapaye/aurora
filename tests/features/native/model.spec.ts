import {
  buildNativeSnapshot,
  parseNativeAction,
  resolveNativeDraft,
} from '~/features/native/model';
import { useStore } from '~/state/store';

describe('native snapshot and incoming action boundaries', () => {
  const now = new Date(2026, 8, 7, 12).getTime();
  it('excludes sample data and distinguishes missing intake from confirmed zero', () => {
    const state = useStore.getState();
    const snapshot = buildNativeSnapshot(
      {
        ...state,
        doses: [{ id: 'demo:dose', mg: 100, timestamp: now }],
        onboarding: { ...state.onboarding, completed: true },
      },
      now,
    );
    expect(snapshot.loggedMg).toBeNull();
    expect(snapshot.activeMg).toBeNull();
    expect(
      buildNativeSnapshot(
        {
          ...state,
          caffeine: { ...state.caffeine, zeroDays: ['2026-09-07'] },
          onboarding: { ...state.onboarding, completed: true },
        },
        now,
      ).loggedMg,
    ).toBe(0);
    expect(snapshot.showLockValues).toBe(false);
  });
  it('caps freshness at midnight and includes only active saved drinks', () => {
    const state = useStore.getState();
    const late = new Date(2026, 8, 7, 23, 59).getTime();
    const snapshot = buildNativeSnapshot(state, late);
    expect(snapshot.expiresAt).toBe(new Date(2026, 8, 8).getTime());
    expect(snapshot.drinks.every((d) => !('note' in d))).toBe(true);
  });
  it.each([
    'aurora://native/log?amount=0',
    'aurora://native/log?amount=2.2',
    'aurora://native/log?amount=2000',
    'aurora://native/log?amount=5&amount=7',
    'aurora://native/log?amount=5&drinkId=x',
    'https://native/log?amount=5',
    'aurora://native/log?amount=NaN',
    'aurora://native/log?amount=5&note=x',
  ])('rejects malformed input %s', (url) =>
    expect(parseNativeAction(url)).toBeNull(),
  );
  it('resolves drink against current library and returns a new confirmation draft', () => {
    const action = parseNativeAction(
      'aurora://native/log?drinkId=personal%3Amydrink',
    );
    const caffeine = {
      ...useStore.getState().caffeine,
      drinks: [
        { id: 'personal:mydrink', label: 'Tea', mg: 70, archived: false },
      ],
    };
    expect(resolveNativeDraft(action!, caffeine, now)).toEqual({
      mg: '70',
      source: 'Tea',
      note: '',
      timestamp: now,
    });
    expect(
      resolveNativeDraft(action!, { ...caffeine, drinks: [] }, now),
    ).toBeNull();
  });
});

it('expires before a next cutoff or bedtime becomes a passed checkpoint', () => {
  const state = useStore.getState();
  const beforeCutoff = new Date(2026, 8, 7, 15, 59).getTime();
  expect(
    buildNativeSnapshot(
      { ...state, prefs: { ...state.prefs, cutoffHour: 16 } },
      beforeCutoff,
    ).expiresAt,
  ).toBe(beforeCutoff + 60000);
  const beforeBed = new Date(2026, 8, 7, 22, 29).getTime();
  expect(buildNativeSnapshot(state, beforeBed).expiresAt).toBe(
    beforeBed + 60000,
  );
  expect(buildNativeSnapshot(state, beforeBed).timezoneOffsetMinutes).toBe(
    new Date(beforeBed).getTimezoneOffset(),
  );
});
