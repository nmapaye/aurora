require('react-native-reanimated').setUpTests();

jest.mock('expo-symbols', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    SymbolView: (props: { testID?: string }) =>
      React.createElement(View, { ...props, testID: props.testID ?? 'sf-symbol' }),
  };
});
