import useNow from '~/hooks/useNow';
import { DosePreview, DoseUndoNotice } from '~/features/caffeine/LoggingTools';
import React, { useState, useSyncExternalStore } from 'react';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import {
  PlanningText as Text,
  PlanningField,
} from '~/features/planning/components';
import { useStore } from '~/state/store';
import {
  pendingNativeAction,
  subscribeNativeActions,
  consumeNativeAction,
} from '~/features/native/actions';
import { resolveNativeDraft } from '~/features/native/model';
import {
  buildCustomDose,
  validateCustomDoseDraft,
} from '~/features/caffeine/logging';
import { navigate } from '~/navigation';
export default function NativeConfirmScreen() {
  const action = useSyncExternalStore(
    subscribeNativeActions,
    pendingNativeAction,
  );
  const state = useStore();
  const now = useNow();
  const [amount, setAmount] = useState<string | null>(null);
  const [error, setError] = useState('');
  const draft = action ? resolveNativeDraft(action, state.caffeine, now) : null;
  const disabled =
    !state.onboarding.completed || !state.onboarding.appWalkthroughCompleted;
  const finish = () => {
    setAmount(null);
    setError('');
    consumeNativeAction();
    navigate('Log');
  };
  return (
    <AppScreen
      title="Confirm Shortcut drink"
      bottomOverlay={<DoseUndoNotice />}
      trailing={<Button title="Cancel" onPress={finish} disabled={disabled} />}
    >
      <Text>
        Review this drink before adding it. Your unfinished Log entry stays
        saved.
      </Text>
      {draft ? (
        <>
          <Text>{draft.source}</Text>
          <PlanningField
            label="Shortcut caffeine amount in milligrams"
            value={amount ?? draft.mg}
            onChange={setAmount}
            disabled={disabled}
            numeric
          />
          <Text>Time will be set to when you confirm.</Text>
          <DosePreview draft={{ ...draft, mg: amount ?? draft.mg }} />
          <Button
            title="Confirm and log drink"
            disabled={disabled}
            onPress={() => {
              const current = {
                ...draft,
                mg: amount ?? draft.mg,
                timestamp: Date.now(),
              };
              const validation = validateCustomDoseDraft(current, Date.now());
              if (!validation.valid) {
                setError(validation.message);
                return;
              }
              state.addDose(
                buildCustomDose(
                  current,
                  () =>
                    `manual:shortcut:${Date.now()}:${Math.random().toString(36).slice(2)}`,
                ),
              );
              finish();
            }}
          />
        </>
      ) : (
        <Text>
          This saved drink is no longer available. Cancel and choose an
          available drink in Shortcuts.
        </Text>
      )}
      {!!error && <Text>{error}</Text>}
      <Button
        title="Cancel Shortcut drink"
        onPress={finish}
        disabled={disabled}
      />
    </AppScreen>
  );
}
