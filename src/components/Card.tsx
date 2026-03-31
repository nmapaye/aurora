import { View, ViewProps, useColorScheme } from 'react-native';
import { getAppPalette } from '~/theme/colors';
export default function Card(props: ViewProps){
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  return (
    <View {...props} style={[
      { backgroundColor: palette.card, borderRadius:16, padding:16, borderWidth:1, borderColor: palette.cardBorder },
      props.style
    ]} />
  );
}
