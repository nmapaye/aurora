import { View, Text, Pressable } from 'react-native';
import ScreenContainer from '~/components/ScreenContainer';
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
    <ScreenContainer horizontalPadding={20} topPadding={20} bottomPadding={20}>
      <View style={{ gap:16 }}>
      <Stepper label="Caffeine half-life (h)" value={prefs.halfLife} setValue={(v)=>setPrefs({ halfLife:v })} />
      <Stepper label="Daily sleep target (h)" value={prefs.targetSleep} setValue={(v)=>setPrefs({ targetSleep:v })} />
      <Stepper label="Daily caffeine limit (mg)" value={prefs.dailyLimitMg} setValue={(v)=>setPrefs({ dailyLimitMg: Math.round(v) })} step={20} min={0} max={1000} />
      <Stepper label="Cutoff hour (0–23)" value={prefs.cutoffHour} setValue={(v)=>setPrefs({ cutoffHour: Math.max(0, Math.min(23, Math.round(v))) })} step={1} min={0} max={23} />
      </View>
    </ScreenContainer>
  );
}
