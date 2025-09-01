import { LinearGradient } from 'expo-linear-gradient';
import { StyleSheet, View } from 'react-native';

export default function AuroraBackground(){
  return (
    <View style={StyleSheet.absoluteFill}>
      <LinearGradient
        colors={['#0B1020', '#060913']}
        start={{ x: 0.2, y: 0.0 }}
        end={{ x: 0.8, y: 1.0 }}
        style={StyleSheet.absoluteFill}
      />
      <LinearGradient
        colors={['rgba(87,117,144,0.15)','rgba(67,170,139,0.10)','rgba(249,65,68,0.06)']}
        start={{ x: 0.0, y: 0.2 }}
        end={{ x: 1.0, y: 0.8 }}
        style={StyleSheet.absoluteFill}
      />
    </View>
  );
}