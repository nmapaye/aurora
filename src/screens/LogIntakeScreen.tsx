import React, { useMemo, useState } from 'react';
import { View, Text, Pressable, TextInput, PlatformColor, ScrollView } from 'react-native';
import * as Haptics from 'expo-haptics';
import { useStore } from '~/state/store';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';

const HIT_TARGET = 44;

function SectionHeader({ title }: { title: string }) {
  return (
    <Text accessibilityRole="header" style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label'), marginBottom: 8 }}>
      {title}
    </Text>
  );
}

function Panel({ children, style }: React.PropsWithChildren<{ style?: any }>) {
  return (
    <View
      style={[
        {
          backgroundColor: PlatformColor('secondarySystemBackground'),
          borderRadius: 16,
          padding: 16,
          borderWidth: 1,
          borderColor: PlatformColor('separator'),
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

function QuickAddGrid({ onAdd }: { onAdd: (mg: number, source?: string) => void }) {
  const presets = [
    { label: '30 mg', mg: 30 },
    { label: '60 mg', mg: 60 },
    { label: '150 mg', mg: 150 },
    { label: '200 mg', mg: 200 },
  ];
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 12 }}>
      {presets.map((p) => (
        <Pressable
          key={p.mg}
          onPress={() => onAdd(p.mg)}
          accessibilityRole="button"
          accessibilityLabel={`Add ${p.mg} milligrams`}
          hitSlop={12}
          style={{
            minHeight: HIT_TARGET,
            minWidth: 88,
            paddingHorizontal: 14,
            paddingVertical: 10,
            borderRadius: 12,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: PlatformColor('secondarySystemBackground'),
            borderWidth: 1,
            borderColor: PlatformColor('separator'),
          }}
        >
          <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>{p.label}</Text>
        </Pressable>
      ))}
    </View>
  );
}

function SegmentedChips<T extends string>({
  options,
  value,
  onChange,
}: {
  options: { key: T; label: string }[];
  value: T;
  onChange: (val: T) => void;
}) {
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
      {options.map((o) => {
        const selected = o.key === value;
        return (
          <Pressable
            key={o.key}
            onPress={() => onChange(o.key)}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            accessibilityLabel={o.label}
            hitSlop={12}
            style={{
              minHeight: HIT_TARGET,
              paddingHorizontal: 14,
              paddingVertical: 10,
              borderRadius: 999,
              backgroundColor: selected ? PlatformColor('systemFill') : PlatformColor('tertiarySystemBackground'),
              borderWidth: 1,
              borderColor: PlatformColor('separator'),
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor(selected ? 'label' : 'label') }}>{o.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export default function LogIntakeScreen() {
  const addDose = useStore((s) => s.addDose);
  const cutoff = useCaffeineCutoff();

  const [mg, setMg] = useState(80);
  const [source, setSource] = useState<'Espresso' | 'Drip' | 'Cold Brew' | 'Tea' | 'Matcha' | 'Other'>('Drip');
  const [note, setNote] = useState('');
  const [ts, setTs] = useState<number>(Date.now());
  const [justSaved, setJustSaved] = useState(false);

  const canSave = useMemo(() => Number.isFinite(mg) && mg > 0 && mg < 2000, [mg]);
  const fmtTime = (t: number) => {
    try { return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(t)); }
    catch { return new Date(t).toLocaleTimeString(); }
  };

  const doAdd = async (amount: number, presetSource?: string) => {
    const id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    try { await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); } catch {}
    addDose({ id, timestamp: Date.now(), mg: amount, source: presetSource });
    try { await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success); } catch {}
    setJustSaved(true);
    setTimeout(() => setJustSaved(false), 1500);
  };

  const onSaveCustom = async () => {
    if (!canSave) return;
    const id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    try { await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium); } catch {}
    addDose({ id, timestamp: ts, mg, source, note: note || undefined });
    try { await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success); } catch {}
    setJustSaved(true);
    setTimeout(() => setJustSaved(false), 1500);
  };

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      showsVerticalScrollIndicator={false}
      contentContainerStyle={{ paddingHorizontal: 16, paddingVertical: 12, paddingBottom: 32 }}
      style={{ flex: 1 }}
    >
      <View style={{ gap: 16 }}>
        {/* Hero / Status */}
        <Panel>
          <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Log intake</Text>
          <Text style={{ fontSize: 22, lineHeight: 28, fontWeight: '600', color: PlatformColor('label') }}>Cutoff date not reached, reach desired performance.</Text>
          {cutoff?.isAfterCutoff ? (
            <Text style={{ marginTop: 6, fontSize: 13, lineHeight: 18, color: PlatformColor('systemRed') }}>
              After cutoff, consider sleep impact before drinking.
            </Text>
          ) : null}
          {justSaved ? (
            <Text style={{ marginTop: 6, fontSize: 13, lineHeight: 18, color: PlatformColor('systemGreen') }}>Saved ✓</Text>
          ) : null}
        </Panel>

        {/* Quick Add */}
        <View>
          <SectionHeader title="Quick Add" />
          <QuickAddGrid onAdd={(amt) => doAdd(amt)} />
        </View>

        {/* Custom Add */}
        <View>
          <SectionHeader title="Custom Add" />
          <Panel style={{ gap: 16 }}>
            {/* Amount row */}
            <View style={{ gap: 8 }}>
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Amount</Text>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
                <Pressable
                  onPress={() => setMg((m) => Math.max(1, Math.round(m - 10)))}
                  accessibilityLabel="Decrease amount"
                  accessibilityRole="button"
                  hitSlop={12}
                  style={{ minWidth: 44, minHeight: 44, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ fontSize: 20, color: PlatformColor('label') }}>−</Text>
                </Pressable>
                <View style={{ flexDirection: 'row', alignItems: 'flex-end' }}>
                  <TextInput
                    keyboardType="number-pad"
                    value={String(mg)}
                    onChangeText={(t) => setMg(Math.max(0, parseInt(t || '0', 10)))}
                    accessibilityLabel="Amount in milligrams"
                    style={{
                      minWidth: 72,
                      fontSize: 34,
                      lineHeight: 41,
                      fontWeight: '600',
                      color: PlatformColor('label'),
                      paddingVertical: 4,
                      paddingHorizontal: 6,
                      borderBottomWidth: 1,
                      borderColor: PlatformColor('separator'),
                      textAlign: 'center',
                    }}
                  />
                  <Text style={{ marginLeft: 6, fontSize: 22, lineHeight: 28, color: PlatformColor('secondaryLabel') }}>mg</Text>
                </View>
                <Pressable
                  onPress={() => setMg((m) => Math.min(2000, Math.round(m + 10)))}
                  accessibilityLabel="Increase amount"
                  accessibilityRole="button"
                  hitSlop={12}
                  style={{ minWidth: 44, minHeight: 44, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ fontSize: 20, color: PlatformColor('label') }}>+</Text>
                </Pressable>
              </View>
            </View>

            {/* Source row */}
            <View style={{ gap: 8 }}>
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Source</Text>
              <SegmentedChips
                value={source}
                onChange={setSource}
                options={[
                  { key: 'Espresso', label: 'Espresso' },
                  { key: 'Drip', label: 'Drip' },
                  { key: 'Cold Brew', label: 'Cold Brew' },
                  { key: 'Tea', label: 'Tea' },
                  { key: 'Matcha', label: 'Matcha' },
                  { key: 'Other', label: 'Other' },
                ]}
              />
            </View>

            {/* Time row */}
            <View style={{ gap: 8 }}>
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Time</Text>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
                <Pressable
                  onPress={() => setTs((t) => t - 15 * 60 * 1000)}
                  accessibilityLabel="Minus fifteen minutes"
                  accessibilityRole="button"
                  hitSlop={12}
                  style={{ minWidth: 44, minHeight: 44, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ fontSize: 20, color: PlatformColor('label') }}>−15</Text>
                </Pressable>
                <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>{fmtTime(ts)}</Text>
                <Pressable
                  onPress={() => setTs((t) => t + 15 * 60 * 1000)}
                  accessibilityLabel="Plus fifteen minutes"
                  accessibilityRole="button"
                  hitSlop={12}
                  style={{ minWidth: 44, minHeight: 44, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ fontSize: 20, color: PlatformColor('label') }}>+15</Text>
                </Pressable>
                <Pressable
                  onPress={() => setTs(Date.now())}
                  accessibilityLabel="Set to now"
                  accessibilityRole="button"
                  hitSlop={12}
                  style={{ minHeight: 36, paddingHorizontal: 12, borderRadius: 8, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('systemFill') }}
                >
                  <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('label') }}>Now</Text>
                </Pressable>
              </View>
            </View>

            {/* Note row */}
            <View style={{ gap: 8 }}>
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Note (optional)</Text>
              <TextInput
                placeholder="e.g., Double shot, with milk"
                placeholderTextColor={PlatformColor('tertiaryLabel')}
                value={note}
                onChangeText={setNote}
                style={{
                  minHeight: 44,
                  borderRadius: 12,
                  paddingHorizontal: 12,
                  paddingVertical: 10,
                  backgroundColor: PlatformColor('tertiarySystemBackground'),
                  borderWidth: 1,
                  borderColor: PlatformColor('separator'),
                  fontSize: 17,
                  color: PlatformColor('label'),
                }}
              />
            </View>

            {/* Actions */}
            <View style={{ flexDirection: 'row', gap: 12 }}>
              <Pressable
                onPress={onSaveCustom}
                disabled={!canSave}
                accessibilityRole="button"
                accessibilityLabel="Add dose"
                style={{
                  flex: 1,
                  minHeight: HIT_TARGET,
                  borderRadius: 12,
                  alignItems: 'center',
                  justifyContent: 'center',
                  backgroundColor: canSave ? PlatformColor('tintColor') : PlatformColor('systemFill'),
                }}
              >
                <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: '#FFFFFF' }}>
                  Add Dose
                </Text>
              </Pressable>
              <Pressable
                onPress={() => {
                  setMg(80); setSource('Drip'); setNote(''); setTs(Date.now());
                }}
                accessibilityRole="button"
                accessibilityLabel="Reset form"
                style={{
                  minWidth: 100,
                  minHeight: HIT_TARGET,
                  paddingHorizontal: 14,
                  borderRadius: 12,
                  alignItems: 'center',
                  justifyContent: 'center',
                  backgroundColor: PlatformColor('secondarySystemBackground'),
                  borderWidth: 1,
                  borderColor: PlatformColor('separator'),
                }}
              >
                <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>Reset</Text>
              </Pressable>
            </View>
          </Panel>
        </View>
      </View>
    </ScrollView>
  );
}
