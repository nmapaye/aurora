import { Platform, TextStyle } from 'react-native';

const systemRegular = Platform.select({ ios: 'System', android: 'sans-serif' })!;
const systemSemibold = Platform.select({ ios: 'System', android: 'sans-serif-medium' })!;

// Keep legacy aliases so existing imports/styles don’t break
export const fontFamily = {
  regular: systemRegular,
  semibold: systemSemibold,
  Inter: systemRegular,
  'Inter-SemiBold': systemSemibold,
};

// Optional preset styles if you used typography tokens elsewhere
export const typography: Record<string, TextStyle> = {
  h1: { fontSize: 28, fontWeight: '600' },
  h2: { fontSize: 22, fontWeight: '600' },
  body: { fontSize: 16, fontWeight: '400' },
  caption: { fontSize: 12, fontWeight: '400' },
};