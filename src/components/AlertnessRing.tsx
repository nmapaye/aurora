import { View, Text } from 'react-native';
import { colors } from '~/theme/colors';
type Props = { value: number };
export default function AlertnessRing({ value }: Props){
  const score = Math.max(0, Math.min(100, Math.round(value||0)));
  return (
    <View style={{
      height:260, alignItems:'center', justifyContent:'center'
    }}>
      <View style={{
        height:240, width:240, borderRadius:120,
        borderWidth:12, borderColor: colors.ring[2],
        alignItems:'center', justifyContent:'center'
      }}>
        <Text style={{ color: colors.textPrimary, fontSize:48, fontWeight:'700' }}>{score}</Text>
        <Text style={{ color: colors.textSecondary }}>Alertness</Text>
      </View>
    </View>
  );
}
  