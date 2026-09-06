import React from 'react';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { PlanningText as Text } from '~/features/planning/components';
import { SectionCard } from '~/components/ui';
import { useStore } from '~/state/store';
import { nativeAvailability } from '~/services/platform/native';
import { goBack } from '~/navigation';
import useNow from '~/hooks/useNow';
export default function NativeAccessScreen() {
  useNow();
  const { ownership, setOwnership, onboarding } = useStore();
  const availability = nativeAvailability();
  const disabled = onboarding.completed && !onboarding.appWalkthroughCompleted;
  return (
    <AppScreen
      title="Widgets and Shortcuts"
      trailing={<Button title="Done" onPress={goBack} />}
    >
      <SectionCard>
        <Text>
          {availability.widgets
            ? 'Add Aurora through the Home Screen widget gallery. Small and medium widgets show your latest local snapshot.'
            : 'Native widgets and Shortcuts are unavailable in this build, including Expo Go. They require the installed iOS app.'}
        </Text>
        <Text>
          Snapshots expire after 15 minutes or at midnight. Open Aurora to
          refresh. Active caffeine is a model estimate.
        </Text>
      </SectionCard>
      <SectionCard>
        <Text>
          Lock Screen values are hidden by default. Enabling them exposes
          caffeine and cutoff information on your Lock Screen.
        </Text>
        <Button
          title={
            ownership.native.showLockValues
              ? 'Hide Lock Screen values'
              : 'Show Lock Screen values'
          }
          disabled={disabled}
          onPress={() =>
            setOwnership({
              ...ownership,
              native: { showLockValues: !ownership.native.showLockValues },
            })
          }
        />
      </SectionCard>
      <SectionCard>
        <Text>
          In Shortcuts, choose “Log a drink in Aurora” with either a saved drink
          or an amount. Aurora always opens for confirmation. “Get Aurora
          status” reads a timestamped snapshot and reports missing or stale
          information.
        </Text>
        <Text>
          {availability.shortcuts
            ? 'Shortcuts supported.'
            : 'Shortcuts require the native app on iOS 16 or later.'}
        </Text>
      </SectionCard>
      <SectionCard>
        <Text>
          {availability.liveActivities
            ? 'A nap timer can appear as a Live Activity. Tap it to return to Aurora, finish the timer and confirm sleep. Canceling or completing removes the activity.'
            : 'Nap Live Activities are unavailable or disabled on this device. The in-app nap timer still works.'}
        </Text>
      </SectionCard>
    </AppScreen>
  );
}
