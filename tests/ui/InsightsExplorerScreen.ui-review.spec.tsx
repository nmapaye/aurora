import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react-native';
import InsightsExplorerScreen from '~/screens/InsightsExplorerScreen';
import { defaultPlanningState } from '~/features/planning/model';
import { useStore } from '~/state/store';

jest.mock('~/navigation', () => ({ navigate: jest.fn(), goBack: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

beforeEach(() => {
  useStore.setState({
    doses: [],
    sleeps: [],
    vigilanceSessions: [],
    planning: defaultPlanningState(),
    caffeine: { ...useStore.getState().caffeine, zeroDays: [] },
  });
});

it.each([320, 900])(
  'chart taps at visible plot endpoints select the first and last times at width %i',
  async (width) => {
    await render(<InsightsExplorerScreen />);
    const chart = screen.getByTestId('inspection-chart', {
      includeHiddenElements: true,
    });
    await fireEvent(chart, 'layout', {
      nativeEvent: { layout: { x: 0, y: 0, width, height: 160 } },
    });
    const svg = screen.getByTestId('inspection-svg', {
      includeHiddenElements: true,
    });
    // SVG's default centered meet scaling can letterbox wide containers.
    // The plot endpoints are x=10 and x=290 in the 300×160 viewBox.
    const stretch = svg.props.align === 'none';
    const scale = stretch ? width / 300 : Math.min(width / 300, 160 / 160);
    const left = stretch ? 0 : (width - 300 * scale) / 2;
    await fireEvent.press(chart, {
      nativeEvent: { locationX: left + 290 * scale, locationY: 80 },
    });
    expect(
      screen.getByRole('button', { name: 'Later inspection time' }),
    ).toBeDisabled();
    await fireEvent.press(chart, {
      nativeEvent: { locationX: left + 10 * scale, locationY: 80 },
    });
    expect(
      screen.getByRole('button', { name: 'Earlier inspection time' }),
    ).toBeDisabled();
  },
);
