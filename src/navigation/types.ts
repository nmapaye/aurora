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
  NativeAccess: undefined;
  NativeConfirm: undefined;
  SummarySettings: undefined;
  ReminderCenter: undefined;
  DataControls: undefined;
  SleepHistory: undefined;
  SleepRoutines: undefined;
  Planning: undefined;
  PlanningTargets: undefined;
  Experiments: undefined;
  InsightsExplorer: undefined;
  CaffeineHistory: undefined;
  DrinkLibrary: undefined;
};
