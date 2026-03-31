// src/navigation/index.tsx
import { createNavigationContainerRef } from '@react-navigation/native';
import type { RootStackParamList, RootTabParamList } from './types';

export const navigationRef = createNavigationContainerRef<RootStackParamList>();

type StandaloneRouteName = Exclude<keyof RootStackParamList, 'Tabs'>;
type AppRouteName = keyof RootTabParamList | StandaloneRouteName;

export function navigate<RouteName extends AppRouteName>(
  name: RouteName,
  params?: RouteName extends keyof RootTabParamList
    ? RootTabParamList[RouteName]
    : RouteName extends StandaloneRouteName
    ? RootStackParamList[RouteName]
    : never
) {
  if (!navigationRef.isReady()) return;
  if (name === 'VigilanceTest') {
    (navigationRef as any).navigate('VigilanceTest', params as any);
    return;
  }
  (navigationRef as any).navigate('Tabs', { screen: name as keyof RootTabParamList, params });
}

export function goBack() {
  if (navigationRef.isReady() && navigationRef.canGoBack()) {
    navigationRef.goBack();
  }
}

export { default as RootNavigator } from './RootNavigator';
export * from './types';
export { default as linking } from './linking';
