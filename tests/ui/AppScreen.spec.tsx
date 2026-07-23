import React from 'react';
import {
  fireEvent,
  render,
  screen,
  userEvent,
} from '@testing-library/react-native';
import {
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';

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

    expect(
      screen.getByTestId('app-screen-content', {
        includeHiddenElements: true,
      }),
    ).toHaveProp('pointerEvents', 'none');
    expect(
      screen.getByTestId('app-screen-content', {
        includeHiddenElements: true,
      }),
    ).toHaveProp('accessibilityElementsHidden', true);
    expect(
      screen.getByTestId('app-screen-content', {
        includeHiddenElements: true,
      }),
    ).toHaveProp(
      'importantForAccessibility',
      'no-hide-descendants',
    );
    expect(
      screen.getByTestId('transformed-header', {
        includeHiddenElements: true,
      }),
    ).toBeOnTheScreen();
    expect(screen.getByText('Coach')).toBeOnTheScreen();

    const styles = StyleSheet.flatten(
      screen.getByTestId('app-screen-scroll').props
        .contentContainerStyle,
    );
    expect(styles.paddingBottom).toBe(244);
  });

  it('hides locked descendants from assistive technology and restores safe defaults', async () => {
    const onSettings = jest.fn();
    const onMetric = jest.fn();
    const onQuickAdd = jest.fn();
    const user = userEvent.setup();
    const screenContents = (locked: boolean) => (
      <AppScreen
        title="Summary"
        interactionEnabled={locked ? false : undefined}
        trailing={
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Settings"
            onPress={onSettings}
          >
            <Text>Settings</Text>
          </Pressable>
        }
      >
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Caffeine metric"
          onPress={onMetric}
        >
          <Text>Caffeine metric</Text>
        </Pressable>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Espresso quick add"
          onPress={onQuickAdd}
        >
          <Text>Espresso quick add</Text>
        </Pressable>
      </AppScreen>
    );
    const { rerender } = await render(screenContents(true));

    expect(
      screen.queryByRole('button', { name: 'Settings' }),
    ).not.toBeOnTheScreen();
    expect(
      screen.queryByRole('button', { name: 'Caffeine metric' }),
    ).not.toBeOnTheScreen();
    expect(
      screen.queryByRole('button', { name: 'Espresso quick add' }),
    ).not.toBeOnTheScreen();
    expect(
      screen.getByTestId('app-screen-content', {
        includeHiddenElements: true,
      }),
    ).toHaveProp('pointerEvents', 'none');

    await rerender(screenContents(false));

    const content = screen.getByTestId('app-screen-content');
    expect(content).toHaveProp('pointerEvents', 'auto');
    expect(content).toHaveProp('accessibilityElementsHidden', false);
    expect(content).toHaveProp(
      'importantForAccessibility',
      'auto',
    );

    await user.press(
      screen.getByRole('button', { name: 'Settings' }),
    );
    await user.press(
      screen.getByRole('button', { name: 'Caffeine metric' }),
    );
    await user.press(
      screen.getByRole('button', { name: 'Espresso quick add' }),
    );

    expect(onSettings).toHaveBeenCalledTimes(1);
    expect(onMetric).toHaveBeenCalledTimes(1);
    expect(onQuickAdd).toHaveBeenCalledTimes(1);
  });
});
