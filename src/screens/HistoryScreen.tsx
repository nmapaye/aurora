import React from 'react';

import AppScreen from '~/components/AppScreen';
import HistoryContent from '~/components/HistoryContent';

export default function HistoryScreen() {
  return (
    <AppScreen
      title="History"
      subtitle="Review, edit, and export logged caffeine and vigilance sessions."
    >
      <HistoryContent />
    </AppScreen>
  );
}
