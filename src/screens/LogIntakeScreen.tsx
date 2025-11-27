import React, { useMemo, useState } from 'react';
import { View, Text, Pressable, TextInput, PlatformColor, Platform, Modal } from 'react-native';
import ScreenContainer from '~/components/ScreenContainer';
import * as Haptics from 'expo-haptics';
import { useStore } from '~/state/store';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';
import DateTimePicker, { DateTimePickerAndroid, DateTimePickerEvent } from '@react-native-community/datetimepicker';

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
  const [iosPickerVisible, setIOSPickerVisible] = useState(false);
  const [iosPendingTime, setIOSPendingTime] = useState<Date>(new Date());

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
  const openTimePicker = () => {
    if (Platform.OS === 'ios') {
      setIOSPendingTime(new Date(ts));
      setIOSPickerVisible(true);
      return;
    }
    DateTimePickerAndroid.open({
      mode: 'time',
      value: new Date(ts),
      onChange: (event, date) => {
        if (event.type === 'set' && date) {
          setTs(date.getTime());
        }
      },
    });
  };
  const onIOSPickerChange = (_event: DateTimePickerEvent, date?: Date) => {
    if (date) setIOSPendingTime(date);
  };
  const confirmIOSPicker = () => {
    setTs(iosPendingTime.getTime());
    setIOSPickerVisible(false);
  };
  const closeIOSPicker = () => setIOSPickerVisible(false);

  return (
    <ScreenContainer keyboardShouldPersistTaps="handled">
      <View style={{ gap: 16 }}>
        {/* Hero / Status */}
        <Panel>
          <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Log intake</Text>
          <Text style={{ fontSize: 22, lineHeight: 28, fontWeight: '600', color: PlatformColor('label') }}>Labor omnia vincit.</Text>
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
                  onPress={openTimePicker}
                  accessibilityLabel="Change logged time"
                  accessibilityRole="button"
                  style={{
                    flex: 1,
                    minHeight: HIT_TARGET,
                    borderRadius: 12,
                    paddingHorizontal: 14,
                    paddingVertical: 10,
                    justifyContent: 'center',
                    backgroundColor: PlatformColor('tertiarySystemBackground'),
                    borderWidth: 1,
                    borderColor: PlatformColor('separator'),
                  }}
                >
                  <Text style={{ fontSize: 22, lineHeight: 28, fontWeight: '600', color: PlatformColor('label') }}>{fmtTime(ts)}</Text>
                  <Text style={{ marginTop: 2, fontSize: 13, lineHeight: 18, color: PlatformColor('tertiaryLabel') }}>Tap to change</Text>
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
      {Platform.OS === 'ios' && iosPickerVisible ? (
        <Modal
          transparent
          animationType="slide"
          presentationStyle="overFullScreen"
          onRequestClose={closeIOSPicker}
        >
          <View style={{ flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(0,0,0,0.35)' }}>
            <Pressable
              style={{ flex: 1 }}
              accessibilityRole="button"
              accessibilityLabel="Dismiss time picker"
              onPress={closeIOSPicker}
            />
            <View
              style={{
                backgroundColor: PlatformColor('systemBackground'),
                paddingBottom: 24,
                paddingTop: 8,
                paddingHorizontal: 16,
                borderTopLeftRadius: 16,
                borderTopRightRadius: 16,
                borderTopWidth: 1,
                borderColor: PlatformColor('separator'),
              }}
            >
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                <Pressable onPress={closeIOSPicker} accessibilityRole="button" accessibilityLabel="Cancel time selection" hitSlop={12}>
                  <Text style={{ fontSize: 17, color: PlatformColor('secondaryLabel') }}>Cancel</Text>
                </Pressable>
                <Pressable onPress={confirmIOSPicker} accessibilityRole="button" accessibilityLabel="Confirm time selection" hitSlop={12}>
                  <Text style={{ fontSize: 17, fontWeight: '600', color: PlatformColor('secondaryLabel') }}>Done</Text>
                </Pressable>
              </View>
              <DateTimePicker
                mode="time"
                display="spinner"
                value={iosPendingTime}
                onChange={onIOSPickerChange}
              />
            </View>
          </View>
        </Modal>
      ) : null}
    </ScreenContainer>
  );
}
