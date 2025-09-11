// src/navigation/RootNavigator.tsx
// Simplified RootNavigator to avoid duplicating NavigationContainer
// Prefer using App.tsx as the root container.
import RootTabs from './RootTabs';

export default function RootNavigator(){
  return <RootTabs />;
}
