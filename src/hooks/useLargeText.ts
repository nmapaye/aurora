import { useWindowDimensions } from 'react-native';

import { isLargeText } from '~/theme/tokens';

// True at text sizes where compact rows should stack. Re-renders when the
// user changes text size.
export default function useLargeText() {
  return isLargeText(useWindowDimensions().fontScale);
}
