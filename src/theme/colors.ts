export type AppScheme = 'light' | 'dark';
export type StatusTone = 'neutral' | 'info' | 'success' | 'warning' | 'error';

export type AppPalette = {
  screen: string;
  groupedBackground: string;
  modalBackground: string;
  card: string;
  cardMuted: string;
  cardBorder: string;
  separator: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  tint: string;
  destructive: string;
  neutralButton: string;
  neutralButtonBorder: string;
  neutralButtonText: string;
  primaryButton: string;
  primaryButtonText: string;
  primaryButtonDisabled: string;
  primaryButtonDisabledText: string;
  secondaryButton: string;
  secondaryButtonBorder: string;
  secondaryButtonText: string;
  plainButtonText: string;
  pressed: string;
  selectionFill: string;
  fieldBackground: string;
  modalScrim: string;
  statusNeutralBackground: string;
  statusNeutralText: string;
  statusInfoBackground: string;
  statusInfoText: string;
  statusSuccessBackground: string;
  statusSuccessText: string;
  statusWarningBackground: string;
  statusWarningText: string;
  statusErrorBackground: string;
  statusErrorText: string;
};

export const colors = {
  bg: '#0B1020',
  card: 'rgba(255,255,255,0.06)',
  textPrimary: 'rgba(255,255,255,0.9)',
  textSecondary: 'rgba(255,255,255,0.7)',
  ring: ['#F94144', '#F8961E', '#90BE6D', '#43AA8B', '#577590'],
  caffeine: '#0A84FF',
  sleep: '#5E5CE6',
};

const lightPalette: AppPalette = {
  screen: '#F2F2F7',
  groupedBackground: '#F2F2F7',
  modalBackground: '#F7F7FA',
  card: '#FFFFFF',
  cardMuted: '#F7F7FA',
  cardBorder: '#D1D1D6',
  separator: '#D1D1D6',
  textPrimary: '#111111',
  textSecondary: '#5A5A5F',
  textTertiary: '#8E8E93',
  tint: '#0A84FF',
  destructive: '#FF3B30',
  neutralButton: '#FFFFFF',
  neutralButtonBorder: '#D1D1D6',
  neutralButtonText: '#111111',
  primaryButton: '#0A84FF',
  primaryButtonText: '#FFFFFF',
  primaryButtonDisabled: '#D1D1D6',
  primaryButtonDisabledText: '#8E8E93',
  secondaryButton: '#EEF5FF',
  secondaryButtonBorder: '#C7DBFF',
  secondaryButtonText: '#0A84FF',
  plainButtonText: '#0A84FF',
  pressed: '#E5E5EA',
  selectionFill: '#EAF2FF',
  fieldBackground: '#F7F7FA',
  modalScrim: 'rgba(0,0,0,0.18)',
  statusNeutralBackground: '#F2F2F7',
  statusNeutralText: '#5A5A5F',
  statusInfoBackground: '#EAF2FF',
  statusInfoText: '#0A84FF',
  statusSuccessBackground: '#EAF9EF',
  statusSuccessText: '#1B8F45',
  statusWarningBackground: '#FFF5E5',
  statusWarningText: '#C67C00',
  statusErrorBackground: '#FFE9E8',
  statusErrorText: '#C9342C',
};

const darkPalette: AppPalette = {
  screen: '#000000',
  groupedBackground: '#000000',
  modalBackground: '#111111',
  card: '#1C1C1E',
  cardMuted: '#2C2C2E',
  cardBorder: '#38383A',
  separator: '#38383A',
  textPrimary: '#FFFFFF',
  textSecondary: '#AEAEB2',
  textTertiary: '#8E8E93',
  tint: '#0A84FF',
  destructive: '#FF453A',
  neutralButton: '#2C2C2E',
  neutralButtonBorder: '#38383A',
  neutralButtonText: '#FFFFFF',
  primaryButton: '#0A84FF',
  primaryButtonText: '#FFFFFF',
  primaryButtonDisabled: '#2C2C2E',
  primaryButtonDisabledText: '#8E8E93',
  secondaryButton: '#11253D',
  secondaryButtonBorder: '#21456D',
  secondaryButtonText: '#6BB4FF',
  plainButtonText: '#6BB4FF',
  pressed: '#2C2C2E',
  selectionFill: '#142033',
  fieldBackground: '#2C2C2E',
  modalScrim: 'rgba(0,0,0,0.42)',
  statusNeutralBackground: '#2C2C2E',
  statusNeutralText: '#C7C7CC',
  statusInfoBackground: '#12304D',
  statusInfoText: '#77B8FF',
  statusSuccessBackground: '#163423',
  statusSuccessText: '#64D68B',
  statusWarningBackground: '#3D2F12',
  statusWarningText: '#FFD36B',
  statusErrorBackground: '#461A18',
  statusErrorText: '#FF9B95',
};

export function getAppPalette(scheme?: AppScheme | null): AppPalette {
  return scheme === 'dark' ? darkPalette : lightPalette;
}

export function getPrimaryButtonColors(
  scheme?: AppScheme | null,
  disabled = false
) {
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
    color: palette.neutralButtonText,
  };
}

export function getSecondaryButtonColors(scheme?: AppScheme | null) {
  const palette = getAppPalette(scheme);
  return {
    backgroundColor: palette.secondaryButton,
    borderColor: palette.secondaryButtonBorder,
    color: palette.secondaryButtonText,
  };
}

export function getStatusColors(
  tone: StatusTone,
  scheme?: AppScheme | null
) {
  const palette = getAppPalette(scheme);
  switch (tone) {
    case 'info':
      return {
        backgroundColor: palette.statusInfoBackground,
        color: palette.statusInfoText,
      };
    case 'success':
      return {
        backgroundColor: palette.statusSuccessBackground,
        color: palette.statusSuccessText,
      };
    case 'warning':
      return {
        backgroundColor: palette.statusWarningBackground,
        color: palette.statusWarningText,
      };
    case 'error':
      return {
        backgroundColor: palette.statusErrorBackground,
        color: palette.statusErrorText,
      };
    default:
      return {
        backgroundColor: palette.statusNeutralBackground,
        color: palette.statusNeutralText,
      };
  }
}
