import React from 'react';
import { StyleSheet, Text } from 'react-native';
import { render, screen } from '@testing-library/react-native';

import {
  HealthChartCard,
  HealthEmptyState,
  HealthFormSheet,
  HealthGroupedList,
  HealthRangeControl,
} from '~/components/health';

describe('HealthRangeControl', () => {
  it('exposes selected state on 44-point range targets', async () => {
    await render(
      <HealthRangeControl
        value="week"
        onChange={jest.fn()}
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
    expect(
      StyleSheet.flatten(screen.getByRole('button', { name: 'W' }).props.style),
    ).toMatchObject({ minHeight: 44, minWidth: 44 });
  });
});

describe('HealthGroupedList', () => {
  it('uses button and disclosure semantics only for pressable rows', async () => {
    await render(
      <HealthGroupedList
        rows={[
          { title: 'Health source', value: 'Connected' },
          { title: 'Show all data', onPress: jest.fn() },
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
    await render(
      <HealthFormSheet
        visible
        title="Add sleep"
        onCancel={jest.fn()}
        onSave={jest.fn()}
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
  });
});
