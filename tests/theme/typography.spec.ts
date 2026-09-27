import {
  eyebrowText,
  fontScaling,
  isLargeText,
  numericText,
  typeRamp,
} from '~/theme/tokens';

describe('shared typography', () => {
  it('never fixes a line height, so scaled text grows its own line box', () => {
    for (const style of [...Object.values(typeRamp), eyebrowText, numericText]) {
      expect(style).not.toHaveProperty('lineHeight');
    }
  });

  it('keeps hero text capped below body text', () => {
    expect(fontScaling.hero).toBeLessThan(fontScaling.body);
  });

  it('treats the largest standard size and every accessibility size as large text', () => {
    // iOS body text: Large 17pt (1.0), xxxLarge 23pt, AX1 28pt, AX5 53pt.
    expect(isLargeText(1)).toBe(false);
    expect(isLargeText(20 / 17)).toBe(false);
    expect(isLargeText(23 / 17)).toBe(true);
    expect(isLargeText(28 / 17)).toBe(true);
    expect(isLargeText(53 / 17)).toBe(true);
  });
});
