import { useColorScheme } from 'react-native';

import { useStore } from '~/state/store';
import type { AppScheme } from '~/theme/colors';

export default function useAppScheme(): AppScheme {
  const systemScheme = useColorScheme();
  const appearanceMode = useStore((state) => state.appearanceMode);

  if (appearanceMode === 'light' || appearanceMode === 'dark') {
    return appearanceMode;
  }

  return systemScheme === 'dark' ? 'dark' : 'light';
}
