import { View } from 'react-native';
import Card from '~/components/Card';
import DoseQuickButtons from '~/components/DoseQuickButtons';
export default function LogIntakeScreen(){
  return <View style={{ flex:1, padding:20, gap:16 }}>
    <Card><DoseQuickButtons/></Card>
  </View>;
}