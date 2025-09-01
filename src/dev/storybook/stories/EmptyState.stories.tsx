import type { Meta, StoryObj } from '@storybook/react';
import React from 'react';
import { View } from 'react-native';
import EmptyState from '~/components/EmptyState';

const meta: Meta<typeof EmptyState> = {
  title: 'Components/EmptyState',
  component: EmptyState,
  decorators: [(Story) => <View style={{ padding: 24, backgroundColor: '#0B1020' }}><Story /></View>],
};
export default meta;

type Story = StoryObj<typeof EmptyState>;

export const NoData: Story = {
  args: {
    title: 'Nothing logged yet',
    message: 'Add your first dose or sleep to see projections.',
    actionLabel: 'Add dose',
    secondaryLabel: 'Start sleep',
  },
};