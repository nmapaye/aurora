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

// RN 0.86's jest preset leaves Switch's native component undefined; render an
// accessible stand-in that toggles like the real control.
jest.mock('react-native/Libraries/Components/Switch/Switch', () => {
  const React = require('react');
  const { Pressable } = require('react-native');
  function MockSwitch({
    value,
    onValueChange,
    disabled,
    ...rest
  }: {
    value?: boolean;
    onValueChange?: (value: boolean) => void;
    disabled?: boolean;
  }) {
    return React.createElement(Pressable, {
      ...rest,
      accessibilityRole: 'switch',
      accessibilityState: { checked: !!value, disabled: !!disabled },
      disabled,
      onPress: () => onValueChange?.(!value),
    });
  }
  return { __esModule: true, default: MockSwitch };
});
