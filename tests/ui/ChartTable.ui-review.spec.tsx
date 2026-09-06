import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react-native';
import ChartTable from '~/components/ChartTable';
import { HealthChartCard } from '~/components/health';
import { ProjectionCurve, timeText } from '~/features/planning/components';

it('exposes chart rows independently of the Health card headline', async () => {
  await render(
    <HealthChartCard
      title="Sleep"
      value="7 hours"
      dateRange="This week"
      accessibilitySummary="Average sleep 7 hours"
    >
      <ChartTable
        title="sleep"
        rows={[
          'Monday: missing sleep records',
          'Tuesday: 7 hours recorded sleep',
        ]}
      />
    </HealthChartCard>,
  );
  expect(screen.getByLabelText('Average sleep 7 hours')).toBeOnTheScreen();
  await fireEvent.press(
    screen.getByRole('button', { name: 'Show sleep table' }),
  );
  expect(
    screen.getByLabelText('Monday: missing sleep records'),
  ).toBeOnTheScreen();
  expect(
    screen.getByLabelText('Tuesday: 7 hours recorded sleep'),
  ).toBeOnTheScreen();
  await fireEvent.press(
    screen.getByRole('button', { name: 'Hide sleep table' }),
  );
  expect(screen.queryByLabelText('Tuesday: 7 hours recorded sleep')).toBeNull();
});

it('provides each projected point with its time and unit', async () => {
  const points = [
    { timestamp: 1800000000000, mg: 100 },
    { timestamp: 1800003600000, mg: 87.5 },
  ];
  await render(<ProjectionCurve points={points} />);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Show scenario projection table' }),
  );
  for (const point of points) {
    expect(
      screen.getByLabelText(
        `${timeText(point.timestamp)}: ${point.mg.toFixed(1)} mg modeled active caffeine`,
      ),
    ).toBeOnTheScreen();
  }
});
