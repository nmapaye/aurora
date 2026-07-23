import { getAppScreenBottomPadding } from '~/components/appScreenLayout';

describe('AppScreen overlay layout', () => {
  it('keeps the existing base and safe-area padding without an overlay', () => {
    expect(getAppScreenBottomPadding(20, 0)).toBe(52);
  });

  it('reserves measured space for a Dynamic Type coach card', () => {
    expect(getAppScreenBottomPadding(20, 180)).toBe(244);
  });
});
