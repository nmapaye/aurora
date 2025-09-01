import { useState } from 'react';
import { View, Text, Pressable } from 'react-native';
import Card from '~/components/Card';
import { useStore } from '~/state/store';

const genId = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;

export default function SleepScreen(){
  const addSleep = useStore(s=>s.addSleep);
  const [start, setStart] = useState<number|null>(null);
  const [mode, setMode] = useState<'sleep'|'nap'>('sleep');

  return (
    <View style={{ flex:1, padding:20, gap:16 }}>
      <Card>
        <View style={{ flexDirection:'row', gap:12 }}>
          <Pressable onPress={()=>setMode('sleep')} style={{ padding:10, borderRadius:12, backgroundColor: mode==='sleep'?'rgba(255,255,255,0.15)':'rgba(255,255,255,0.06)' }}>
            <Text style={{ color:'white' }}>Main sleep</Text>
          </Pressable>
          <Pressable onPress={()=>setMode('nap')} style={{ padding:10, borderRadius:12, backgroundColor: mode==='nap'?'rgba(255,255,255,0.15)':'rgba(255,255,255,0.06)' }}>
            <Text style={{ color:'white' }}>Nap</Text>
          </Pressable>
        </View>
      </Card>
      <Card>
        {start===null ? (
          <Pressable onPress={()=>setStart(Date.now())} style={{ padding:14, borderRadius:12, backgroundColor:'rgba(255,255,255,0.12)' }}>
            <Text style={{ color:'white', textAlign:'center' }}>Start {mode}</Text>
          </Pressable>
        ) : (
          <Pressable onPress={()=>{
              const end = Date.now();
              addSleep({ id: genId(), start, end, type: mode });
              setStart(null);
            }} style={{ padding:14, borderRadius:12, backgroundColor:'rgba(255,255,255,0.12)' }}>
            <Text style={{ color:'white', textAlign:'center' }}>Stop and Save</Text>
          </Pressable>
        )}
        <Text style={{ color:'rgba(255,255,255,0.7)', marginTop:8 }}>
          {start ? `Recording… ${Math.round((Date.now()-start)/60000)} min` : 'Idle'}
        </Text>
      </Card>
    </View>
  );
}