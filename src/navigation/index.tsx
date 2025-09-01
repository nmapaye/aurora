// src/navigation/index.tsx
import { createNavigationContainerRef } from '@react-navigation/native';
import type { RootTabParamList } from './types';

export const navigationRef = createNavigationContainerRef<RootTabParamList>();

// Typed navigate helper (safe for routes with or without params)
export function navigate<RouteName extends keyof RootTabParamList>(
  name: RouteName,
  params?: RootTabParamList[RouteName]
) {
  if (!navigationRef.isReady()) return;
  // React Navigation uses variadic tuple overloads; cast is expected here
  navigationRef.navigate(name as never, params as never);
}

export { default as RootNavigator } from './RootNavigator';
export * from './types';
export { default as linking } from './linking';