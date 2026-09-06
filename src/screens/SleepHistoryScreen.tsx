import useNow from '~/hooks/useNow';
import { SegmentedControl } from '~/components/ui';
import {
  overlapPairs,
  sleepHistory,
  sleepJournalKey,
  type SleepFilters,
} from '~/features/sleep/upgrades';
import { isLocalDateKey } from '~/utils/calendar';
import React, { createRef, useMemo, useRef, useState } from 'react';
import { Alert, Text, TextInput, View } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import {
  HealthEmptyState,
  HealthFormSheet,
  HealthGroupedList,
} from '~/components/health';
import {
  isManualSleep,
  validateManualSleep,
} from '~/features/sleep/manualSleep';
import {
  formatSleepDuration,
  sleepSourceLabel,
} from '~/features/sleep/presentation';
import { goBack } from '~/navigation';
import { useStore } from '~/state/store';
import useAppScheme from '~/hooks/useAppScheme';
import useReduceMotion from '~/hooks/useReduceMotion';
import { getAppPalette } from '~/theme/colors';
import { radii, spacing, typeRamp } from '~/theme/tokens';

function formatDateTime(timestamp: number) {
  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(timestamp));
}

export default function SleepHistoryScreen() {
  const palette = getAppPalette(useAppScheme());
  const reduceMotion = useReduceMotion();
  const sleeps = useStore((state) => state.sleeps);
  const updateManualSleep = useStore((state) => state.updateManualSleep);
  const removeManualSleep = useStore((state) => state.removeManualSleep);
  const now = useNow();
  const saveSleepJournal = useStore((s) => s.saveSleepJournal);
  const routines = useStore((s) => s.sleepRoutines);
  const onboarding = useStore((s) => s.onboarding);
  const disabled = onboarding.completed && !onboarding.appWalkthroughCompleted;
  const [filters, setFilters] = useState<SleepFilters>({
    query: '',
    source: 'all',
    type: 'all',
  });
  const [journalId, setJournalId] = useState<string | null>(null);
  const [quality, setQuality] = useState('3'),
    [journalNote, setJournalNote] = useState('');
  const journalRefs = useRef(new Map<string, React.RefObject<View | null>>());
  const [journalTriggerId, setJournalTriggerId] = useState<string | null>(null);
  const overlaps = useMemo(() => overlapPairs(sleeps), [sleeps]);
  const [editingId, setEditingId] = useState<string | undefined>();
  const editing = sleeps.find((sleep) => sleep.id === editingId);
  const [start, setStart] = useState(0);
  const [end, setEnd] = useState(0);
  const [note, setNote] = useState('');
  const [pickerField, setPickerField] = useState<'start' | 'end' | undefined>();
  const validation = validateManualSleep({ start, end });
  const editTriggerRefs = useRef(
    new Map<string, React.RefObject<View | null>>(),
  );
  const returnFocusRef = editingId
    ? editTriggerRefs.current.get(editingId)
    : undefined;
  const sorted = useMemo(
    () =>
      sleepHistory(
        sleeps,
        {
          ...filters,
          from:
            filters.from && isLocalDateKey(filters.from)
              ? filters.from
              : undefined,
          to: filters.to && isLocalDateKey(filters.to) ? filters.to : undefined,
        },
        routines.annotations,
        now,
      ),
    [sleeps, filters, routines.annotations, now],
  );

  const edit = (id: string) => {
    const item = sleeps.find((sleep) => sleep.id === id);
    if (disabled || !item || !isManualSleep(item.id)) return;
    setEditingId(item.id);
    setStart(item.start);
    setEnd(item.end);
    setNote(item.note ?? '');
  };
  const save = () => {
    if (disabled || !editing || !validation.valid) return;
    updateManualSleep(editing.id, {
      start,
      end,
      ...(note.trim() ? { note: note.trim() } : { note: undefined }),
    });
    setPickerField(undefined);
    setEditingId(undefined);
  };
  const remove = (id: string) => {
    if (disabled || !isManualSleep(id)) return;
    Alert.alert(
      'Delete sleep session?',
      'This manual sleep session will be removed.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            const current = useStore.getState();
            if (
              !current.onboarding.completed ||
              current.onboarding.appWalkthroughCompleted
            )
              removeManualSleep(id);
          },
        },
      ],
    );
  };

  return (
    <AppScreen
      title="Sleep History"
      trailing={<Button title="Close" variant="plain" onPress={goBack} />}
    >
      <TextInput
        accessibilityLabel="Search sleep notes"
        placeholder="Search sleep and journal notes"
        value={filters.query}
        onChangeText={(query) => setFilters({ ...filters, query })}
        style={{ color: palette.textPrimary, minHeight: 44 }}
      />
      <SegmentedControl
        value={filters.source}
        onChange={(source) => setFilters({ ...filters, source })}
        options={[
          { key: 'all', label: 'All sources' },
          { key: 'Manual', label: 'Manual records' },
          { key: 'Health', label: 'Health records' },
          { key: 'Sample Data', label: 'Samples' },
        ]}
      />
      <SegmentedControl
        value={filters.type}
        onChange={(type) => setFilters({ ...filters, type })}
        options={[
          { key: 'all', label: 'All types' },
          { key: 'sleep', label: 'Main sleep' },
          { key: 'nap', label: 'Naps' },
        ]}
      />
      <TextInput
        accessibilityLabel="Sleep history from date"
        placeholder="From YYYY-MM-DD"
        value={filters.from ?? ''}
        onChangeText={(from) => setFilters({ ...filters, from })}
        style={{ color: palette.textPrimary, minHeight: 44 }}
      />
      <TextInput
        accessibilityLabel="Sleep history to date"
        placeholder="Through YYYY-MM-DD"
        value={filters.to ?? ''}
        onChangeText={(to) => setFilters({ ...filters, to })}
        style={{ color: palette.textPrimary, minHeight: 44 }}
      />
      {(filters.from && !isLocalDateKey(filters.from)) ||
      (filters.to && !isLocalDateKey(filters.to)) ? (
        <Text accessibilityRole="alert">
          Enter a valid date as YYYY-MM-DD. Invalid date filters are not
          applied.
        </Text>
      ) : null}
      <Button
        title="Reset sleep filters"
        variant="plain"
        onPress={() => setFilters({ query: '', source: 'all', type: 'all' })}
      />
      {overlaps.length ? (
        <Text style={{ ...typeRamp.body, color: palette.textPrimary }}>
          {overlaps.length} overlapping pairs. Review flagged manual entries
          below to edit or delete them. Health records remain read-only.
          Overlapping time counts once.
        </Text>
      ) : null}
      {sorted.length ? (
        <View style={{ gap: spacing.sm }}>
          {sorted.map((sleep) => {
            const manual = isManualSleep(sleep.id);
            const annotationId = sleepJournalKey(
              sleep.id,
              sleeps,
              now,
              routines.annotations,
            );
            const annotation = routines.annotations[annotationId];
            return (
              <View
                key={sleep.id}
                style={{
                  gap: spacing.xs,
                  borderRadius: radii.card,
                  padding: spacing.md,
                  backgroundColor: palette.card,
                }}
              >
                <HealthGroupedList
                  rows={[
                    {
                      title: sleepSourceLabel(sleep.id),
                      subtitle: `${formatDateTime(sleep.start)} to ${formatDateTime(sleep.end)} · ${formatSleepDuration(sleep.end - sleep.start)} · ${sleep.type === 'nap' ? 'Nap' : 'Main sleep'}`,
                      value: manual ? 'Editable' : 'Read-only',
                    },
                    ...(sleep.note
                      ? [{ title: 'Note', subtitle: sleep.note }]
                      : []),
                  ]}
                />
                {overlaps.some((pair) =>
                  pair.some((item) => item.id === sleep.id),
                ) ? (
                  <Text
                    style={{
                      ...typeRamp.footnote,
                      color: palette.textSecondary,
                    }}
                  >
                    Overlaps another session:{' '}
                    {overlaps
                      .filter((pair) =>
                        pair.some((item) => item.id === sleep.id),
                      )
                      .map((pair) => pair.find((item) => item.id !== sleep.id)!)
                      .map(
                        (item) =>
                          `${sleepSourceLabel(item.id)} ${formatDateTime(item.start)} to ${formatDateTime(item.end)}`,
                      )
                      .join('; ')}
                  </Text>
                ) : null}
                {annotation ? (
                  <Text
                    style={{ ...typeRamp.body, color: palette.textPrimary }}
                  >
                    Quality {annotation.quality}/5. {annotation.note}
                  </Text>
                ) : null}
                {!sleep.id.startsWith('demo:') ? (
                  <Button
                    ref={(() => {
                      const existing = journalRefs.current.get(sleep.id);
                      if (existing) return existing;
                      const ref = createRef<View>();
                      journalRefs.current.set(sleep.id, ref);
                      return ref;
                    })()}
                    title={
                      annotation ? 'Edit sleep journal' : 'Add sleep journal'
                    }
                    disabled={disabled}
                    variant="plain"
                    onPress={() => {
                      setJournalTriggerId(sleep.id);
                      setJournalId(annotationId);
                      setQuality(String(annotation?.quality ?? 3));
                      setJournalNote(annotation?.note ?? '');
                    }}
                  />
                ) : null}
                {manual ? (
                  <View style={{ flexDirection: 'row', gap: spacing.sm }}>
                    <Button
                      ref={(() => {
                        const existing = editTriggerRefs.current.get(sleep.id);
                        if (existing) return existing;
                        const created = createRef<View>();
                        editTriggerRefs.current.set(sleep.id, created);
                        return created;
                      })()}
                      title="Edit manual sleep"
                      disabled={disabled}
                      variant="plain"
                      onPress={() => edit(sleep.id)}
                    />
                    <Button
                      title="Delete manual sleep"
                      disabled={disabled}
                      variant="plain"
                      role="destructive"
                      onPress={() => remove(sleep.id)}
                    />
                  </View>
                ) : null}
              </View>
            );
          })}
        </View>
      ) : (
        <HealthEmptyState
          message={
            sleeps.length
              ? 'No sleep sessions match these filters.'
              : 'No sleep sessions yet.'
          }
          detail="Add a manual session or connect Health."
          symbol="bed.double.fill"
          fallback="bed"
        />
      )}
      <HealthFormSheet
        visible={Boolean(journalId)}
        title="Morning sleep journal"
        reduceMotion={reduceMotion}
        returnFocusRef={
          journalTriggerId
            ? journalRefs.current.get(journalTriggerId)
            : undefined
        }
        onCancel={() => setJournalId(null)}
        saveLabel="Save journal"
        saveDisabled={disabled}
        onSave={() => {
          if (!journalId || disabled) return;
          saveSleepJournal(journalId, Number(quality), journalNote.trim());
          setJournalId(null);
        }}
      >
        <Text style={{ ...typeRamp.body, color: palette.textPrimary }}>
          Your subjective rating for this sleep episode. Connected Health
          segments share this journal. 1 is very poor, 5 is very good. This
          annotation does not change the source sleep record.
        </Text>
        <SegmentedControl
          value={quality}
          onChange={setQuality}
          options={[1, 2, 3, 4, 5].map((n) => ({
            key: String(n),
            label: String(n),
          }))}
        />
        <TextInput
          accessibilityLabel="Journal note"
          value={journalNote}
          onChangeText={setJournalNote}
          maxLength={2000}
          multiline
          style={{ color: palette.textPrimary, minHeight: 88 }}
        />
      </HealthFormSheet>
      <HealthFormSheet
        visible={Boolean(editing)}
        title="Edit Sleep"
        reduceMotion={reduceMotion}
        returnFocusRef={returnFocusRef}
        onCancel={() => {
          setPickerField(undefined);
          setEditingId(undefined);
        }}
        onSave={save}
        saveLabel="Save changes"
        saveDisabled={disabled || !validation.valid}
      >
        <Button
          title={`Start · ${formatDateTime(start)}`}
          accessibilityLabel="Start time"
          accessibilityValue={{ text: formatDateTime(start) }}
          variant="tinted"
          onPress={() => setPickerField('start')}
        />
        <Button
          title={`End · ${formatDateTime(end)}`}
          accessibilityLabel="End time"
          accessibilityValue={{ text: formatDateTime(end) }}
          variant="tinted"
          onPress={() => setPickerField('end')}
        />
        {pickerField ? (
          <DateTimePicker
            testID={`history-${pickerField}-picker`}
            value={new Date(pickerField === 'start' ? start : end)}
            mode="datetime"
            display="spinner"
            onChange={(_event, date) => {
              if (date) {
                if (pickerField === 'start') setStart(date.getTime());
                else setEnd(date.getTime());
              }
            }}
          />
        ) : null}
        <TextInput
          accessibilityLabel="Sleep note"
          value={note}
          onChangeText={setNote}
          placeholder="Optional note"
          placeholderTextColor={palette.textTertiary}
          style={{
            minHeight: 44,
            borderWidth: 1,
            borderColor: palette.separator,
            borderRadius: radii.control,
            color: palette.textPrimary,
            paddingHorizontal: spacing.sm,
          }}
        />
        {!validation.valid ? (
          <Text
            accessibilityRole="alert"
            style={{ ...typeRamp.footnote, color: palette.destructive }}
          >
            {validation.message}
          </Text>
        ) : null}
      </HealthFormSheet>
    </AppScreen>
  );
}
