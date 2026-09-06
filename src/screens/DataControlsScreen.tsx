import React, { useRef, useState } from 'react';
import { View } from 'react-native';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { SectionCard } from '~/components/ui';
import { HealthFormSheet } from '~/components/health';
import { PlanningText as Text } from '~/features/planning/components';
import {
  createBackup,
  localRecordCounts,
  LOCAL_CATEGORIES,
  type Backup,
  type LocalCategory,
} from '~/features/ownership/backup';
import {
  pickBackupFile,
  shareBackupFile,
} from '~/services/storage/backupFiles';
import { cancelAuroraReminders } from '~/services/platform/reminderCenter';
import useReduceMotion from '~/hooks/useReduceMotion';
import { useStore } from '~/state/store';
import { goBack } from '~/navigation';
const labels: Record<LocalCategory, string> = {
  caffeine: 'Caffeine entries, caffeine-free days and draft',
  sleep: 'Sleep records, journal annotations and nap timer',
  vigilance: 'Vigilance tests',
  checkIns: 'Alertness check-ins',
  plans: 'Scenarios, experiments, reduction and budget plans',
  drinks: 'Personal drinks and favorites',
  routines: 'Weekly schedule, date exceptions and reminders',
  all: 'All Aurora data and settings',
};
export default function DataControlsScreen() {
  const state = useStore(),
    counts = localRecordCounts(state),
    reduceMotion = useReduceMotion();
  const [backup, setBackup] = useState<Backup | null>(null),
    [selection, setSelection] = useState<LocalCategory[]>([]),
    [confirmDelete, setConfirmDelete] = useState(false),
    [busy, setBusy] = useState(false),
    [message, setMessage] = useState('');
  const importRef = useRef<View>(null),
    deleteRef = useRef<View>(null);
  const disabled =
    busy ||
    (state.onboarding.completed && !state.onboarding.appWalkthroughCompleted);
  const run = async (action: () => Promise<void>) => {
    setBusy(true);
    setMessage('');
    try {
      await action();
    } catch (error) {
      setMessage(
        error instanceof Error
          ? error.message
          : 'Unable to complete this action.',
      );
    } finally {
      setBusy(false);
    }
  };
  return (
    <AppScreen
      title="Data & Privacy"
      trailing={<Button title="Done" onPress={goBack} />}
    >
      <SectionCard>
        <Text>
          Your records stay on this device. Backups are unencrypted JSON files
          and may contain personal sleep, caffeine, notes and test information.
          Anyone with the file can read it. Choose the destination in the system
          share sheet.
        </Text>
        <Text>
          Exports exclude Sample Data and OS permission grants. Import replaces
          local Aurora data only after preview and confirmation. Apple Health
          records are never changed. Notification permission remains controlled
          by this device.
        </Text>
        <Button
          title="Export unencrypted backup"
          disabled={disabled}
          onPress={() =>
            void run(async () => {
              await shareBackupFile(
                createBackup(useStore.getState(), Date.now()),
              );
              setMessage(
                'Backup share sheet closed. Saving a copy depends on the destination you selected.',
              );
            })
          }
        />
        <Button
          ref={importRef}
          title="Import Aurora backup"
          disabled={disabled}
          onPress={() =>
            void run(async () => {
              const selected = await pickBackupFile();
              if (selected) setBackup(selected);
            })
          }
        />
      </SectionCard>
      <SectionCard>
        <Text>Local records</Text>
        {Object.entries(counts).map(([category, count]) => (
          <Text key={category}>
            {labels[category as LocalCategory]}: {count}
          </Text>
        ))}
        <Text>
          Counts include Sample Data shown locally, drafts, journal annotations
          and a pending timer. Schedule count includes seven weekday entries.
          Plans include saved allocations; plan preferences reset with that
          category.
        </Text>
        <Text>
          Deleting local Health imports does not delete Apple Health records. A
          later Health refresh can import them again. Deleting all data also
          resets onboarding, appearance and preferences, stops reminders and
          cancels any pending nap.
        </Text>
        {LOCAL_CATEGORIES.map((category) => (
          <Button
            key={category}
            title={`${selection.includes(category) ? 'Selected' : 'Select'}: ${labels[category]}`}
            disabled={disabled}
            onPress={() =>
              setSelection(
                selection.includes(category)
                  ? selection.filter((x) => x !== category)
                  : category === 'all'
                    ? ['all']
                    : [...selection.filter((x) => x !== 'all'), category],
              )
            }
          />
        ))}
        <Button
          ref={deleteRef}
          title="Delete selected local data"
          role="destructive"
          disabled={disabled || selection.length === 0}
          onPress={() => setConfirmDelete(true)}
        />
      </SectionCard>
      {message ? <Text>{message}</Text> : null}
      <HealthFormSheet
        visible={backup !== null}
        title="Preview backup replacement"
        saveLabel="Replace local Aurora data"
        saveDisabled={disabled}
        returnFocusRef={importRef}
        reduceMotion={reduceMotion}
        onCancel={() => {
          if (!busy) setBackup(null);
        }}
        onSave={() =>
          void run(async () => {
            if (!backup) return;
            await cancelAuroraReminders();
            useStore.getState().replaceBackup(backup);
            setBackup(null);
            setMessage(
              'Local Aurora data replaced. OS permissions were not restored.',
            );
          })
        }
      >
        {backup ? (
          <>
            <Text>
              Backup created {new Date(backup.createdAt).toLocaleString()}.
              Version {backup.version}.
            </Text>
            {Object.entries(localRecordCounts(backup.data)).map(
              ([category, count]) => (
                <Text key={category}>
                  {labels[category as LocalCategory]}: {count}
                </Text>
              ),
            )}
            <Text>
              This replaces every local record and preference with this backup.
              Your current data will be removed. Export it first if you need a
              copy. A restored nap stays unconfirmed until you confirm it in
              Aurora.
            </Text>
          </>
        ) : null}
      </HealthFormSheet>
      <HealthFormSheet
        visible={confirmDelete}
        title="Confirm local deletion"
        saveLabel="Delete local data"
        saveDisabled={disabled}
        reduceMotion={reduceMotion}
        returnFocusRef={deleteRef}
        onCancel={() => {
          if (!busy) setConfirmDelete(false);
        }}
        onSave={() =>
          void run(async () => {
            if (selection.includes('all') || selection.includes('routines'))
              await cancelAuroraReminders();
            useStore.getState().deleteLocalCategories(selection);
            setConfirmDelete(false);
            setSelection([]);
            setMessage(
              'Selected local data deleted. Apple Health records were not changed.',
            );
          })
        }
      >
        <Text>
          Delete {selection.map((x) => labels[x]).join(', ')}? This cannot be
          undone. Other categories remain unless you selected all data.
        </Text>
      </HealthFormSheet>
    </AppScreen>
  );
}
