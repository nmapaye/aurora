import { View, Text, Pressable } from 'react-native';
import Card from '~/components/Card';
import { useStore } from '~/state/store';

function Stepper({label, value, setValue, step=0.5, min=0.5, max=16}:{label:string; value:number; setValue:(n:number)=>void; step?:number; min?:number; max?:number}){
  return (
    <Card>
      <Text style={{ color:'white', marginBottom:8 }}>{label}: {value.toFixed(1)}</Text>
      <View style={{ flexDirection:'row', gap:12 }}>
        <Pressable onPress={()=>setValue(Math.max(min, value-step))} style={{ padding:10, borderRadius:12, backgroundColor:'rgba(255,255,255,0.12)' }}>
          <Text style={{ color:'white' }}>−</Text>
        </Pressable>
        <Pressable onPress={()=>setValue(Math.min(max, value+step))} style={{ padding:10, borderRadius:12, backgroundColor:'rgba(255,255,255,0.12)' }}>
          <Text style={{ color:'white' }}>+</Text>
        </Pressable>
      </View>
    </Card>
  );
}

export default function SettingsScreen(){
  const prefs = useStore(s=>s.prefs);
  const setPrefs = useStore(s=>s.setPrefs);
  return (
    <View style={{ flex:1, padding:20, gap:16 }}>
      <Stepper label="Caffeine half-life (h)" value={prefs.halfLife} setValue={(v)=>setPrefs({ halfLife:v })} />
      <Stepper label="Daily sleep target (h)" value={prefs.targetSleep} setValue={(v)=>setPrefs({ targetSleep:v })} />
    </View>
  );
}