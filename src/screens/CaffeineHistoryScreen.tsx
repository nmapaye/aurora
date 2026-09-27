import React from 'react';

import AppScreen from '~/components/AppScreen';
import HistoryContent from '~/components/HistoryContent';

// Pushed with a native navigation bar (back button, swipe back); the large
// title stays in content like the tab screens.
export default function CaffeineHistoryScreen() {
  return (
    <AppScreen title="Caffeine History" trailing={false}>
      <HistoryContent initialSection="doses" focused />
    </AppScreen>
  );
}
