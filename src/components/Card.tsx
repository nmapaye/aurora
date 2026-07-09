import { View, ViewProps } from 'react-native';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
export default function Card(props: ViewProps){
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <View {...props} style={[
      {
        backgroundColor: palette.card,
        borderRadius: 16,
        padding: 16,
        borderWidth: scheme === 'dark' ? 0 : 1,
        borderColor: palette.cardBorder,
      },
      props.style
    ]} />
  );
}
