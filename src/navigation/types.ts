import type { NavigatorScreenParams } from '@react-navigation/native';

export type RootTabParamList = {
  Summary: undefined;
  Log: undefined;
  Sleep: undefined;
  Insights: undefined;
};

export type RootStackParamList = {
  Tabs: NavigatorScreenParams<RootTabParamList> | undefined;
  VigilanceTest: undefined;
  Settings: undefined;
  SleepHistory: undefined;
  SleepRoutines: undefined;
  Planning: undefined;
  PlanningTargets: undefined;
  Experiments: undefined;
  InsightsExplorer: undefined;
  CaffeineHistory: undefined;
  DrinkLibrary: undefined;
};
