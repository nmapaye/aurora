import { CAFFEINE_PRESETS } from '~/features/caffeine/presets';

describe('CAFFEINE_PRESETS', () => {
  it('provides the approved quick-add presets in display order', () => {
    expect(CAFFEINE_PRESETS).toEqual([
      {
        id: 'espresso',
        label: 'Espresso',
        mg: 60,
        symbol: 'cup.and.saucer.fill',
      },
      {
        id: 'drip',
        label: 'Drip',
        mg: 95,
        symbol: 'cup.and.saucer.fill',
      },
      {
        id: 'matcha',
        label: 'Matcha',
        mg: 70,
        symbol: 'leaf.fill',
      },
      {
        id: 'energy',
        label: 'Energy',
        mg: 160,
        symbol: 'bolt.fill',
      },
    ]);
  });
});
