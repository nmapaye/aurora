import { View, ViewProps } from 'react-native';
import { colors } from '~/theme/colors';
export default function Card(props: ViewProps){
  return (
    <View {...props} style={[
      { backgroundColor: colors.card, borderRadius:16, padding:16, borderWidth:1, borderColor:'rgba(255,255,255,0.08)' },
      props.style
    ]} />
  );
}
  