import { useAlertnessSeries } from '~/hooks/useAlertnessSeries';
import { View } from 'react-native';
import Svg, { Path } from 'react-native-svg';
export default function TimelineGraph(){
  const { series } = useAlertnessSeries();
  const w = 320, h = 120;
  const max = 100, min = 0;
  const path = series.map((p,i)=>{
    const x = (i/(series.length-1))*w;
    const y = h - ((p.score-min)/(max-min))*h;
    return `${i?'L':'M'}${x},${y}`;
  }).join(' ');
  return <View style={{ alignItems:'center' }}>
    <Svg width={w} height={h}><Path d={path} stroke="white" strokeOpacity={0.7} fill="none" strokeWidth={2}/></Svg>
  </View>;
}