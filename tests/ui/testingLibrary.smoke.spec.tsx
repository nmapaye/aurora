import React from 'react';
import { render, screen } from '@testing-library/react-native';
import { Text } from 'react-native';

describe('React Native component test harness', () => {
  it('renders React 19 host components through the async API', async () => {
    await render(<Text accessibilityRole="header">Aurora UI test</Text>);

    expect(
      screen.getByRole('header', { name: 'Aurora UI test' }),
    ).toBeOnTheScreen();
  });
});
