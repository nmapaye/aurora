import React from 'react';
import {
  fireEvent,
  render,
  screen,
} from '@testing-library/react-native';
import { StyleSheet, Text, View } from 'react-native';

import AppScreen from '~/components/AppScreen';

jest.mock('~/hooks/useAdaptiveLayout', () => ({
  __esModule: true,
  default: () => ({
    isWideLayout: false,
    topChromeBuffer: 0,
    horizontalPadding: 16,
    contentMaxWidth: 600,
  }),
}));
jest.mock('~/hooks/useAppScheme', () => ({
  __esModule: true,
  default: () => 'light',
}));
jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 20, left: 0 }),
}));

describe('AppScreen walkthrough controls', () => {
  it('locks content, transforms the header, and reserves overlay space', async () => {
    await render(
      <AppScreen
        title="Summary"
        trailing={<Text>Settings</Text>}
        interactionEnabled={false}
        bottomOverlay={<Text>Coach</Text>}
        headerTransform={(header) => (
          <View testID="transformed-header">{header}</View>
        )}
      >
        <Text>Main content</Text>
      </AppScreen>,
    );

    await fireEvent(
      screen.getByTestId('app-screen-overlay'),
      'layout',
      {
        nativeEvent: {
          layout: { x: 0, y: 0, width: 320, height: 180 },
        },
      },
    );

    expect(screen.getByTestId('app-screen-content')).toHaveProp(
      'pointerEvents',
      'none',
    );
    expect(screen.getByTestId('transformed-header')).toBeOnTheScreen();
    expect(screen.getByText('Coach')).toBeOnTheScreen();

    const styles = StyleSheet.flatten(
      screen.getByTestId('app-screen-scroll').props
        .contentContainerStyle,
    );
    expect(styles.paddingBottom).toBe(244);
  });
});
