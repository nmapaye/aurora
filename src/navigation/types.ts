import type { NavigatorScreenParams } from '@react-navigation/native';

export type RootTabParamList = {
  Home: undefined;
  Log: undefined;
  Sleep: undefined;
  Insights: { section?: 'summary' | 'trends' | 'history' } | undefined;
};

export type RootStackParamList = {
  Tabs: NavigatorScreenParams<RootTabParamList> | undefined;
  VigilanceTest: undefined;
  Settings: undefined;
};
