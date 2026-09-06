import React from 'react';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { DrinkLibrary } from '~/features/caffeine/LoggingTools';
import { goBack } from '~/navigation';
import { useStore } from '~/state/store';
import { isAppWalkthroughPending } from '~/features/appWalkthrough/model';
export default function DrinkLibraryScreen() {
  const pending = useStore((s) => isAppWalkthroughPending(s.onboarding));
  return (
    <AppScreen
      title="Drinks & Favorites"
      interactionEnabled={!pending}
      trailing={<Button title="Close" variant="plain" onPress={goBack} />}
    >
      <DrinkLibrary />
    </AppScreen>
  );
}
