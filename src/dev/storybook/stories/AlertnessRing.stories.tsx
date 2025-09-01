import type { Meta, StoryObj } from '@storybook/react';
import React from 'react';
import { View } from 'react-native';
import AlertnessRing from '~/components/AlertnessRing';

const meta: Meta<typeof AlertnessRing> = {
  title: 'Components/AlertnessRing',
  component: AlertnessRing,
  decorators: [(Story) => <View style={{ padding: 24, backgroundColor: '#0B1020' }}><Story /></View>],
};
export default meta;

type Story = StoryObj<typeof AlertnessRing>;

export const Default: Story = { args: { value: 72 } };
export const Low: Story    = { args: { value: 18 } };
export const High: Story   = { args: { value: 96 } };