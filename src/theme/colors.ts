import { ink, ivory, seaGlass } from '~/theme/brand';

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
  caffeineAccent: string;
  activeCaffeineAccent: string;
  sleepAccent: string;
  vigilanceAccent: string;
  cutoffAccent: string;
  healthAccent: string;
  napAccent: string;
  warningFill: string;
  warningForeground: string;
  onDestructive: string;
};

// Calm luxury: warm ivory surfaces in light mode, deep ink in dark mode, and a
// single sea-glass accent. Data accents are desaturated so charts stay quiet.
// Text roles meet WCAG AA on `card`; accents used as label text do as well.
const lightPalette: AppPalette = {
  screen: ivory[200],
  groupedBackground: ivory[200],
  modalBackground: ivory[100],
  card: ivory[50],
  cardMuted: ivory[300],
  cardBorder: ivory[400],
  separator: ivory[400],
  textPrimary: '#1A1F24',
  textSecondary: '#5B6168',
  textTertiary: '#767B80',
  tint: seaGlass[700],
  destructive: '#A8402E',
  neutralButton: ivory[50],
  neutralButtonBorder: ivory[400],
  neutralButtonText: '#1A1F24',
  primaryButton: seaGlass[700],
  primaryButtonText: ivory[50],
  primaryButtonDisabled: ivory[400],
  primaryButtonDisabledText: '#767B80',
  secondaryButton: seaGlass[100],
  secondaryButtonBorder: '#C5DDD7',
  secondaryButtonText: seaGlass[700],
  plainButtonText: seaGlass[700],
  pressed: '#ECE5D9',
  selectionFill: seaGlass[100],
  fieldBackground: ivory[100],
  modalScrim: 'rgba(26,31,36,0.24)',
  statusNeutralBackground: ivory[300],
  statusNeutralText: '#5B6168',
  statusInfoBackground: seaGlass[100],
  statusInfoText: seaGlass[700],
  statusSuccessBackground: '#E5EEE0',
  statusSuccessText: '#46693A',
  statusWarningBackground: '#F5EAD5',
  statusWarningText: '#855711',
  statusErrorBackground: '#F5E2DC',
  statusErrorText: '#9E3B2A',
  caffeineAccent: '#9A5B2E',
  activeCaffeineAccent: '#5E7A3E',
  sleepAccent: '#4A5590',
  vigilanceAccent: seaGlass[600],
  cutoffAccent: '#7D4F80',
  healthAccent: '#A8434F',
  napAccent: '#3F7690',
  warningFill: '#E6C47A',
  warningForeground: '#2A2418',
  onDestructive: ivory[50],
};

const darkPalette: AppPalette = {
  screen: ink[900],
  groupedBackground: ink[900],
  modalBackground: ink[850],
  card: ink[850],
  cardMuted: ink[800],
  cardBorder: ink[700],
  separator: ink[700],
  textPrimary: ink[100],
  textSecondary: ink[300],
  textTertiary: ink[400],
  tint: seaGlass[300],
  destructive: '#E8806C',
  neutralButton: ink[800],
  neutralButtonBorder: ink[600],
  neutralButtonText: ink[100],
  primaryButton: seaGlass[300],
  primaryButtonText: ink[900],
  primaryButtonDisabled: ink[800],
  primaryButtonDisabledText: ink[500],
  secondaryButton: seaGlass[800],
  secondaryButtonBorder: '#24504A',
  secondaryButtonText: seaGlass[200],
  plainButtonText: seaGlass[200],
  pressed: '#232A30',
  selectionFill: seaGlass[800],
  fieldBackground: ink[800],
  modalScrim: 'rgba(0,0,0,0.52)',
  statusNeutralBackground: ink[800],
  statusNeutralText: '#C3C8CD',
  statusInfoBackground: seaGlass[800],
  statusInfoText: seaGlass[200],
  statusSuccessBackground: '#1D2B1C',
  statusSuccessText: '#A3C795',
  statusWarningBackground: '#31281A',
  statusWarningText: '#E6C27F',
  statusErrorBackground: '#3A201B',
  statusErrorText: '#F0A594',
  caffeineAccent: '#D9A26E',
  activeCaffeineAccent: '#A9C48A',
  sleepAccent: '#A3ADE6',
  vigilanceAccent: seaGlass[300],
  cutoffAccent: '#CDA3D0',
  healthAccent: '#E8939E',
  napAccent: '#93C3DA',
  warningFill: '#E6C47A',
  warningForeground: '#1A1610',
  onDestructive: ink[900],
};

export function getAppPalette(scheme?: AppScheme | null): AppPalette {
  return scheme === 'dark' ? darkPalette : lightPalette;
}

export function getPrimaryButtonColors(
  scheme?: AppScheme | null,
  disabled = false,
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

export type SurfaceVariant = 'raised' | 'muted' | 'field';

// One border and fill rule for every card-like surface in both schemes.
export function getSurfaceColors(
  variant: SurfaceVariant,
  scheme?: AppScheme | null,
) {
  const palette = getAppPalette(scheme);
  const backgroundColor =
    variant === 'raised'
      ? palette.card
      : variant === 'muted'
        ? palette.cardMuted
        : palette.fieldBackground;
  return { backgroundColor, borderColor: palette.cardBorder };
}

export function getStatusColors(tone: StatusTone, scheme?: AppScheme | null) {
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
