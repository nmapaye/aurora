export const colors = {
  bg: '#0B1020',
  card: 'rgba(255,255,255,0.06)',
  textPrimary: 'rgba(255,255,255,0.9)',
  textSecondary: 'rgba(255,255,255,0.7)',
  ring: ['#F94144','#F8961E','#90BE6D','#43AA8B','#577590'],
  caffeine: '#6EE7F9',
  sleep: '#A78BFA',
};

export type AppScheme = 'light' | 'dark';

type AppPalette = {
  screen: string;
  card: string;
  cardBorder: string;
  textPrimary: string;
  textSecondary: string;
  neutralButton: string;
  neutralButtonBorder: string;
  primaryButton: string;
  primaryButtonText: string;
  primaryButtonDisabled: string;
  primaryButtonDisabledText: string;
};

const lightPalette: AppPalette = {
  screen: '#F4F7FB',
  card: '#FFFFFF',
  cardBorder: '#D7DEE7',
  textPrimary: '#0F172A',
  textSecondary: '#475569',
  neutralButton: '#EEF2F7',
  neutralButtonBorder: '#D7DEE7',
  primaryButton: '#2563EB',
  primaryButtonText: '#FFFFFF',
  primaryButtonDisabled: '#CBD5E1',
  primaryButtonDisabledText: '#64748B',
};

const darkPalette: AppPalette = {
  screen: '#0B1020',
  card: 'rgba(255,255,255,0.06)',
  cardBorder: 'rgba(255,255,255,0.08)',
  textPrimary: 'rgba(255,255,255,0.92)',
  textSecondary: 'rgba(255,255,255,0.7)',
  neutralButton: 'rgba(255,255,255,0.1)',
  neutralButtonBorder: 'rgba(255,255,255,0.14)',
  primaryButton: '#6EE7F9',
  primaryButtonText: '#0B1020',
  primaryButtonDisabled: 'rgba(255,255,255,0.12)',
  primaryButtonDisabledText: 'rgba(255,255,255,0.55)',
};

export function getAppPalette(scheme?: AppScheme | null): AppPalette {
  return scheme === 'dark' ? darkPalette : lightPalette;
}

export function getPrimaryButtonColors(scheme?: AppScheme | null, disabled = false) {
  const palette = getAppPalette(scheme);
  return disabled
    ? {
        backgroundColor: palette.primaryButtonDisabled,
        color: palette.primaryButtonDisabledText,
      }
    : {
        backgroundColor: palette.primaryButton,
        color: palette.primaryButtonText,
      };
}

export function getNeutralButtonColors(scheme?: AppScheme | null) {
  const palette = getAppPalette(scheme);
  return {
    backgroundColor: palette.neutralButton,
    borderColor: palette.neutralButtonBorder,
    color: palette.textPrimary,
  };
}
