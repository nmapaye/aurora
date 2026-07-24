import React from 'react';
import { Text } from 'react-native';
import { render, screen, userEvent } from '@testing-library/react-native';

import {
  HealthChartCard,
  HealthEmptyState,
  HealthFormSheet,
  HealthGroupedList,
  HealthHighlightCard,
  HealthRangeControl,
} from '~/components/health';

describe('HealthRangeControl', () => {
  it('exposes selected state on 44-point range targets', async () => {
    const onChange = jest.fn();
    const user = userEvent.setup();
    await render(
      <HealthRangeControl
        value="week"
        onChange={onChange}
        options={[
          { value: 'week', label: 'W' },
          { value: 'month', label: 'M' },
        ]}
      />,
    );

    expect(screen.getByRole('button', { name: 'W' })).toHaveProp(
      'accessibilityState',
      { selected: true },
    );
    expect(screen.getByRole('button', { name: 'M' })).toHaveProp(
      'accessibilityState',
      { selected: false },
    );
    expect(screen.getByRole('button', { name: 'W' })).toHaveStyle({
      minHeight: 44,
      minWidth: 44,
    });

    await user.press(screen.getByRole('button', { name: 'M' }));

    expect(onChange).toHaveBeenCalledWith('month');
  });
});

describe('HealthGroupedList', () => {
  it('uses button and disclosure semantics only for pressable rows', async () => {
    const onShowAllData = jest.fn();
    const user = userEvent.setup();
    await render(
      <HealthGroupedList
        rows={[
          { title: 'Health source', value: 'Connected' },
          { title: 'Show all data', onPress: onShowAllData },
        ]}
      />,
    );

    expect(
      screen.queryByRole('button', { name: 'Health source' }),
    ).not.toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Show all data' })).toHaveProp(
      'accessibilityHint',
      'Opens details',
    );
    expect(screen.queryByTestId('health-row-disclosure-0')).not.toBeOnTheScreen();
    expect(screen.getByTestId('health-row-disclosure-1')).toBeOnTheScreen();

    await user.press(screen.getByRole('button', { name: 'Show all data' }));

    expect(onShowAllData).toHaveBeenCalledTimes(1);
  });
});

describe('HealthHighlightCard', () => {
  it('presents its label, value, and detail as one concise highlight', async () => {
    await render(
      <HealthHighlightCard
        label="Sleep duration"
        value="7h 20m"
        detail="40 min under target"
      />,
    );

    expect(
      screen.getByLabelText('Sleep duration: 7h 20m. 40 min under target.'),
    ).toBeOnTheScreen();
  });
});

describe('HealthChartCard', () => {
  it('exposes one concise summary and an honest no-data state', async () => {
    await render(
      <HealthChartCard
        title="Caffeine intake"
        value="—"
        dateRange="Last 7 days"
        accessibilitySummary="Caffeine intake, Last 7 days: no data."
        emptyState={<HealthEmptyState message="No caffeine data for this range." />}
      />,
    );

    expect(
      screen.getByLabelText('Caffeine intake, Last 7 days: no data.'),
    ).toBeOnTheScreen();
    expect(screen.getByText('No caffeine data for this range.')).toBeOnTheScreen();
    expect(screen.queryByText('0 mg')).not.toBeOnTheScreen();
  });
});

describe('HealthFormSheet', () => {
  it('exposes modal semantics, a heading, Cancel, and Save', async () => {
    const onCancel = jest.fn();
    const onSave = jest.fn();
    const user = userEvent.setup();
    await render(
      <HealthFormSheet
        visible
        title="Add sleep"
        onCancel={onCancel}
        onSave={onSave}
      >
        <Text>Form fields</Text>
      </HealthFormSheet>,
    );

    expect(screen.getByLabelText('Add sleep')).toHaveProp(
      'accessibilityViewIsModal',
      true,
    );
    expect(screen.getByRole('header', { name: 'Add sleep' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Save' })).toBeOnTheScreen();

    await user.press(screen.getByRole('button', { name: 'Cancel' }));
    await user.press(screen.getByRole('button', { name: 'Save' }));

    expect(onCancel).toHaveBeenCalledTimes(1);
    expect(onSave).toHaveBeenCalledTimes(1);
  });
});
