// Native module transforms and React rendering can exceed Jest's 5s default on a cold worker.
// Keep the longer budget within UI suites; unit tests retain the default.
jest.setTimeout(30_000);

jest.mock('react-native-worklets', () => require('react-native-worklets/src/mock'));

require('react-native-reanimated').setUpTests();

jest.mock('expo-symbols', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    SymbolView: (props: { testID?: string }) =>
      React.createElement(View, { ...props, testID: props.testID ?? 'sf-symbol' }),
  };
});
