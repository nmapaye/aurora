import { View, Pressable, Text } from 'react-native';
import { useStore } from '~/state/store';

const presets = [
  { label:'Espresso', mg:75 },
  { label:'Drip', mg:95 },
  { label:'Cold Brew', mg:180 },
  { label:'Matcha', mg:60 },
  { label:'Tea', mg:40 },
];

const genId = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;

export default function DoseQuickButtons(){
  const addDose = useStore(s=>s.addDose);
  return (
    <View style={{ flexDirection:'row', flexWrap:'wrap', gap:12 }}>
      {presets.map(p=>(
        <Pressable
          key={p.label}
          onPress={()=>addDose({ id: genId(), timestamp: Date.now(), mg: p.mg, source: p.label })}
          style={{ paddingVertical:10, paddingHorizontal:14, borderRadius:999,
                   backgroundColor:'rgba(255,255,255,0.06)', borderWidth:1,
                   borderColor:'rgba(255,255,255,0.12)' }}>
          <Text style={{ color:'rgba(255,255,255,0.9)' }}>{p.label}</Text>
        </Pressable>
      ))}
    </View>
  );
}