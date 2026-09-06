import { navigate, navigationRef } from '~/navigation';
jest.mock('~/navigation/RootNavigator', () => ({
  __esModule: true,
  default: () => null,
}));
beforeEach(() => {
  jest.spyOn(navigationRef, 'isReady').mockReturnValue(true);
  jest.spyOn(navigationRef, 'navigate').mockImplementation(jest.fn());
});
afterEach(() => jest.restoreAllMocks());
it.each([
  'VigilanceTest',
  'Settings',
  'SleepHistory',
  'SleepRoutines',
  'CaffeineHistory',
  'DrinkLibrary',
  'Planning',
  'PlanningTargets',
  'Experiments',
  'InsightsExplorer',
] as const)('dispatches %s as a standalone route', (route) => {
  navigate(route);
  expect(navigationRef.navigate).toHaveBeenCalledWith(route, undefined);
});
it('keeps primary tabs nested', () => {
  navigate('Sleep');
  expect(navigationRef.navigate).toHaveBeenCalledWith('Tabs', {
    screen: 'Sleep',
    params: undefined,
  });
});
