import React, { useMemo, useState } from 'react';
import { Alert, Text, TextInput, View } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { HealthEmptyState, HealthFormSheet, HealthGroupedList } from '~/components/health';
import { isManualSleep, validateManualSleep } from '~/features/sleep/manualSleep';
import { formatSleepDuration, sleepSourceLabel } from '~/features/sleep/presentation';
import { goBack } from '~/navigation';
import { useStore } from '~/state/store';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { radii, spacing, typeRamp } from '~/theme/tokens';

function inputTimestamp(value: string) {
  const result = Number(value);
  return Number.isFinite(result) ? result : Number.NaN;
}

export default function SleepHistoryScreen() {
  const palette = getAppPalette(useAppScheme());
  const sleeps = useStore((state) => state.sleeps);
  const updateManualSleep = useStore((state) => state.updateManualSleep);
  const removeManualSleep = useStore((state) => state.removeManualSleep);
  const [editingId, setEditingId] = useState<string | undefined>();
  const editing = sleeps.find((sleep) => sleep.id === editingId);
  const [start, setStart] = useState('');
  const [end, setEnd] = useState('');
  const [note, setNote] = useState('');
  const validation = validateManualSleep({ start: inputTimestamp(start), end: inputTimestamp(end) });
  const sorted = useMemo(() => [...sleeps].sort((left, right) => right.end - left.end), [sleeps]);

  const edit = (id: string) => {
    const item = sleeps.find((sleep) => sleep.id === id);
    if (!item || !isManualSleep(item.id)) return;
    setEditingId(item.id);
    setStart(String(item.start));
    setEnd(String(item.end));
    setNote(item.note ?? '');
  };
  const save = () => {
    if (!editing || !validation.valid) return;
    updateManualSleep(editing.id, {
      start: inputTimestamp(start),
      end: inputTimestamp(end),
      ...(note.trim() ? { note: note.trim() } : { note: undefined }),
    });
    setEditingId(undefined);
  };
  const remove = (id: string) => {
    if (!isManualSleep(id)) return;
    Alert.alert('Delete sleep session?', 'This manual sleep session will be removed.', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Delete', style: 'destructive', onPress: () => removeManualSleep(id) },
    ]);
  };

  return (
    <AppScreen title="Sleep History" trailing={<Button title="Close" variant="plain" onPress={goBack} />}>
      {sorted.length ? <View style={{ gap: spacing.sm }}>
        {sorted.map((sleep) => {
          const manual = isManualSleep(sleep.id);
          return <View key={sleep.id} style={{ gap: spacing.xs, borderRadius: radii.card, padding: spacing.md, backgroundColor: palette.card }}>
            <HealthGroupedList rows={[
              { title: sleepSourceLabel(sleep.id), subtitle: `${new Date(sleep.start).toLocaleDateString()} · ${formatSleepDuration(sleep.end - sleep.start)}`, value: manual ? 'Editable' : 'Read-only' },
              ...(sleep.note ? [{ title: 'Note', subtitle: sleep.note }] : []),
            ]} />
            {manual ? <View style={{ flexDirection: 'row', gap: spacing.sm }}><Button title="Edit manual sleep" variant="plain" onPress={() => edit(sleep.id)} /><Button title="Delete manual sleep" variant="plain" role="destructive" onPress={() => remove(sleep.id)} /></View> : null}
          </View>;
        })}
      </View> : <HealthEmptyState message="No sleep sessions yet." detail="Add a manual session or connect Health." symbol="bed.double.fill" fallback="bed" />}
      <HealthFormSheet visible={Boolean(editing)} title="Edit Sleep" onCancel={() => setEditingId(undefined)} onSave={save} saveLabel="Save changes" saveDisabled={!validation.valid}>
        <TextInput accessibilityLabel="Start time" keyboardType="numeric" value={start} onChangeText={setStart} style={{ minHeight: 44, borderWidth: 1, borderColor: palette.separator, borderRadius: radii.control, color: palette.textPrimary, paddingHorizontal: spacing.sm }} />
        <TextInput accessibilityLabel="End time" keyboardType="numeric" value={end} onChangeText={setEnd} style={{ minHeight: 44, borderWidth: 1, borderColor: palette.separator, borderRadius: radii.control, color: palette.textPrimary, paddingHorizontal: spacing.sm }} />
        <TextInput accessibilityLabel="Sleep note" value={note} onChangeText={setNote} placeholder="Optional note" placeholderTextColor={palette.textTertiary} style={{ minHeight: 44, borderWidth: 1, borderColor: palette.separator, borderRadius: radii.control, color: palette.textPrimary, paddingHorizontal: spacing.sm }} />
        {!validation.valid ? <Text accessibilityRole="alert" style={{ ...typeRamp.footnote, color: palette.destructive }}>{validation.message}</Text> : null}
      </HealthFormSheet>
    </AppScreen>
  );
}
