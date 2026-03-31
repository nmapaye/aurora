import type { Meta, StoryObj } from '@storybook/react';
import React from 'react';
import { View } from 'react-native';

import Button from '~/components/Button';
import { ListRow, SectionCard, SectionTitle, SegmentedControl, StatTile } from '~/components/ui';

function UIKitShowcase() {
  return (
    <View style={{ gap: 16 }}>
      <SectionCard>
        <SectionTitle>Today</SectionTitle>
        <View style={{ flexDirection: 'row', gap: 12 }}>
          <StatTile label="Active caffeine" value="84 mg" detail="Projected now" />
          <StatTile label="Cutoff" value="2:10 PM" detail="Protecting bedtime" />
        </View>
      </SectionCard>

      <SectionCard>
        <SegmentedControl
          value="summary"
          onChange={() => {}}
          options={[
            { key: 'summary', label: 'Summary' },
            { key: 'trends', label: 'Trends' },
            { key: 'history', label: 'History' },
          ]}
        />
        <ListRow
          title="Suggested bedtime"
          subtitle="Projected active caffeine 28 mg"
          value="10:30 PM"
        />
        <ListRow
          title="Latest vigilance"
          subtitle="Median reaction 286 ms"
          value="76"
        />
      </SectionCard>

      <View style={{ flexDirection: 'row', gap: 10 }}>
        <Button title="Primary" onPress={() => {}} />
        <Button title="Secondary" variant="secondary" onPress={() => {}} />
      </View>
    </View>
  );
}

const meta: Meta<typeof UIKitShowcase> = {
  title: 'Components/UIKit',
  component: UIKitShowcase,
  decorators: [
    (Story) => (
      <View style={{ flex: 1, padding: 24, backgroundColor: '#F2F2F7' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;

type Story = StoryObj<typeof UIKitShowcase>;

export const Overview: Story = {};
