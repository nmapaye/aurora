import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { colors } from '../theme/colors';

type SleepType = 'sleep' | 'nap';
export type SleepSession = { id: string; start: number; end: number; type: SleepType };

type Props = {
  session: SleepSession;
  onPress?: (s: SleepSession) => void;
  onDelete?: (id: string) => void;
  testID?: string;
};

const ms = 1;
const s = 1000 * ms;
const m = 60 * s;
const h = 60 * m;

function fmtTime(t: number) {
  return new Date(t).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
}
function fmtDate(t: number) {
  return new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}
function fmtDuration(ms: number) {
  const hours = Math.floor(ms / h);
  const mins = Math.round((ms % h) / m);
  if (hours && mins) return `${hours}h ${mins}m`;
  if (hours) return `${hours}h`;
  return `${mins}m`;
}

export default function SleepSessionItem({ session, onPress, onDelete, testID }: Props) {
  const { id, start, end, type } = session;
  const sameDay = new Date(start).toDateString() === new Date(end).toDateString();
  const durationMs = Math.max(0, end - start);

  const accent =
    type === 'sleep'
      ? colors.sleep // purple for main sleep
      : 'rgba(110, 231, 249, 0.9)'; // cyan-ish for nap

  return (
    <Pressable
      testID={testID}
      accessibilityRole="button"
      accessibilityLabel={`Sleep from ${fmtTime(start)} to ${fmtTime(end)}`}
      onPress={() => onPress?.(session)}
      style={({ pressed }) => [
        styles.row,
        { backgroundColor: colors.card, borderColor: 'rgba(255,255,255,0.12)' },
        pressed && styles.pressed,
      ]}
    >
      <View style={[styles.accent, { backgroundColor: accent }]} />

      <View style={styles.col}>
        <Text style={styles.title}>
          {type === 'sleep' ? 'Main sleep' : 'Nap'} · {fmtDuration(durationMs)}
        </Text>
        <Text style={styles.sub}>
          {sameDay ? (
            <>
              {fmtTime(start)} – {fmtTime(end)}
            </>
          ) : (
            <>
              {fmtDate(start)} {fmtTime(start)} → {fmtDate(end)} {fmtTime(end)}
            </>
          )}
        </Text>
      </View>

      {onDelete ? (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Delete sleep session"
          onPress={() => onDelete(id)}
          style={({ pressed }) => [styles.delete, pressed && { opacity: 0.8 }]}
        >
          <Text style={styles.deleteText}>Delete</Text>
        </Pressable>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 14,
    borderRadius: 12,
    borderWidth: 1,
    gap: 12,
    minHeight: 56,
  },
  pressed: { transform: [{ scale: 0.99 }] },
  accent: {
    width: 6,
    alignSelf: 'stretch',
    borderRadius: 999,
    opacity: 0.9,
  },
  col: { flex: 1 },
  title: {
    color: colors.textPrimary,
    fontSize: 15,
    fontWeight: '600',
  },
  sub: {
    color: colors.textSecondary,
    fontSize: 13,
    marginTop: 2,
  },
  delete: {
    paddingVertical: 6,
    paddingHorizontal: 10,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.18)',
    backgroundColor: 'rgba(255,255,255,0.06)',
  },
  deleteText: {
    color: colors.textPrimary,
    fontSize: 12,
    fontWeight: '600',
  },
});