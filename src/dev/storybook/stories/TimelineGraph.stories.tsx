import type { Meta, StoryObj } from '@storybook/react';
import React from 'react';
import { View } from 'react-native';
import DoseQuickButtons from '~/components/DoseQuickButtons';
import { useStore } from '~/state/store';

const meta: Meta<typeof DoseQuickButtons> = {
  title: 'Components/DoseQuickButtons',
  component: DoseQuickButtons,
  decorators: [(Story) => <View style={{ padding: 24, backgroundColor: '#0B1020' }}><Story /></View>],
};
export default meta;

type Story = StoryObj<typeof DoseQuickButtons>;

export const Default: Story = {
  render: () => {
    // no-op store consumer to ensure Zustand initializes
    useStore.getState();
    return <DoseQuickButtons />;
  },
};