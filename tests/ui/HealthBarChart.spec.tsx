import React from 'react';
import { render, screen } from '@testing-library/react-native';

import { HealthBarChart } from '~/components/health';

describe('HealthBarChart', () => {
  it('draws a labelled reference line and date endpoints, hidden from VoiceOver', async () => {
    await render(
      <HealthBarChart
        testID="chart"
        points={[{ key: 1, value: 120 }, { key: 2, value: null }, { key: 3, value: 450 }]}
        max={450}
        color="#000"
        reference={{ value: 400, label: '400 mg limit' }}
        startLabel="Sep 20"
        endLabel="Today"
      />,
    );

    expect(screen.getByTestId('chart', { includeHiddenElements: true })).toHaveProp('accessibilityElementsHidden', true);
    expect(screen.getByText('400 mg limit', { includeHiddenElements: true })).toBeTruthy();
    expect(screen.getByText('Sep 20', { includeHiddenElements: true })).toBeTruthy();
    expect(screen.getByText('Today', { includeHiddenElements: true })).toBeTruthy();
  });

  it('keeps the reference inside the chart even when every day is under it', async () => {
    await render(
      <HealthBarChart
        testID="chart"
        height={100}
        points={[{ key: 1, value: 50 }]}
        max={50}
        color="#000"
        reference={{ value: 400, label: 'limit' }}
      />,
    );

    const bottom = screen.getByTestId('chart-reference', { includeHiddenElements: true }).props.style.bottom;
    expect(bottom).toBeGreaterThan(0);
    expect(bottom).toBeLessThanOrEqual(100);
  });
});
