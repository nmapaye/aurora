import React from 'react';

import AppScreen from '~/components/AppScreen';
import HistoryContent from '~/components/HistoryContent';

export default function CaffeineHistoryScreen() {
  return (
    <AppScreen title="Caffeine History">
      <HistoryContent initialSection="doses" focused />
    </AppScreen>
  );
}
