import React from 'react';

import { useStore } from '~/state/store';
import { isAppWalkthroughPending } from '~/features/appWalkthrough/model';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { DoseUndoNotice } from '~/features/caffeine/LoggingTools';
import HistoryContent from '~/components/HistoryContent';
import { goBack } from '~/navigation';

export default function CaffeineHistoryScreen() {
  const pending = useStore((s) => isAppWalkthroughPending(s.onboarding));
  return (
    <AppScreen
      title="Caffeine History"
      interactionEnabled={!pending}
      bottomOverlay={<DoseUndoNotice />}
      trailing={<Button title="Close" variant="plain" onPress={goBack} />}
    >
      <HistoryContent initialSection="doses" focused />
    </AppScreen>
  );
}
