import React from 'react';
import { Platform } from 'react-native';
import { render, screen } from '@testing-library/react-native';

import AppSymbol from '~/components/AppSymbol';

jest.mock('@expo/vector-icons', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    Ionicons: (props: object) =>
      React.createElement(View, { ...props, testID: 'ionicon-fallback' }),
  };
});

describe('AppSymbol', () => {
  const originalPlatform = Platform.OS;

  afterEach(() => {
    (Platform as { OS: string }).OS = originalPlatform;
  });

  it('forwards the iOS SF Symbol name, size, tint, and accessibility label', async () => {
    (Platform as { OS: string }).OS = 'ios';

    await render(
      <AppSymbol
        name="cup.and.saucer.fill"
        fallback="cafe"
        size={20}
        tintColor="#0A84FF"
        accessibilityLabel="Espresso"
      />,
    );

    expect(screen.getByTestId('sf-symbol')).toHaveProp(
      'name',
      'cup.and.saucer.fill',
    );
    expect(screen.getByTestId('sf-symbol')).toHaveProp('tintColor', '#0A84FF');
    expect(screen.getByTestId('sf-symbol')).toHaveStyle({ width: 20, height: 20 });
    expect(screen.getByLabelText('Espresso')).toBeOnTheScreen();
  });

  it('renders its Ionicons fallback outside iOS', async () => {
    (Platform as { OS: string }).OS = 'android';

    await render(
      <AppSymbol
        name="bolt.fill"
        fallback="flash"
        size={24}
        tintColor="#0A84FF"
      />,
    );

    expect(screen.getByTestId('ionicon-fallback')).toHaveProp('name', 'flash');
    expect(screen.getByTestId('ionicon-fallback')).toHaveProp('size', 24);
    expect(screen.getByTestId('ionicon-fallback')).toHaveProp('color', '#0A84FF');
  });
});
