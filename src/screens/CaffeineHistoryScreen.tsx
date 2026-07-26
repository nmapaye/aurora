import React from 'react';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import HistoryContent from '~/components/HistoryContent';
import { goBack } from '~/navigation';

export default function CaffeineHistoryScreen() {
  return (
    <AppScreen
      title="Caffeine History"
      trailing={<Button title="Close" variant="plain" onPress={goBack} />}
    >
      <HistoryContent initialSection="doses" focused />
    </AppScreen>
  );
}
