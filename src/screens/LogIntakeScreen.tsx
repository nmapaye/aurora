import React, { useMemo, useState } from 'react';
import {
  Modal,
  Platform,
  View,
  useColorScheme,
} from 'react-native';
import DateTimePicker, {
  DateTimePickerAndroid,
  DateTimePickerEvent,
} from '@react-native-community/datetimepicker';
import * as Haptics from 'expo-haptics';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import {
  FieldInput,
  FormField,
  SectionCard,
  SectionTitle,
  SegmentedControl,
} from '~/components/ui';
import { getAppPalette } from '~/theme/colors';
import { useStore } from '~/state/store';

type SourceOption =
  | 'Espresso'
  | 'Drip'
  | 'Cold Brew'
  | 'Tea'
  | 'Matcha'
  | 'Other';

function fmtTime(timestamp: number) {
  try {
    return new Intl.DateTimeFormat(undefined, {
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toLocaleTimeString();
  }
}

export default function LogIntakeScreen() {
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const addDose = useStore((s) => s.addDose);

  const [mg, setMg] = useState(80);
  const [source, setSource] = useState<SourceOption>('Drip');
  const [note, setNote] = useState('');
  const [timestamp, setTimestamp] = useState<number>(Date.now());
  const [iosPickerVisible, setIOSPickerVisible] = useState(false);
  const [iosPendingTime, setIOSPendingTime] = useState<Date>(new Date());

  const canSave = useMemo(
    () => Number.isFinite(mg) && mg > 0 && mg < 2000,
    [mg]
  );

  const commitDose = async (amount: number, presetSource?: string) => {
    const id = `${Date.now().toString(36)}-${Math.random()
      .toString(36)
      .slice(2)}`;
    try {
      await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    } catch {}
    addDose({
      id,
      timestamp: presetSource ? Date.now() : timestamp,
      mg: amount,
      source: presetSource ?? source,
      note: presetSource ? undefined : note || undefined,
    });
    try {
      await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    } catch {}
  };

  const reset = () => {
    setMg(80);
    setSource('Drip');
    setNote('');
    setTimestamp(Date.now());
  };

  const openTimePicker = () => {
    if (Platform.OS === 'ios') {
      setIOSPendingTime(new Date(timestamp));
      setIOSPickerVisible(true);
      return;
    }
    DateTimePickerAndroid.open({
      mode: 'time',
      value: new Date(timestamp),
      onChange: (event, date) => {
        if (event.type === 'set' && date) {
          setTimestamp(date.getTime());
        }
      },
    });
  };

  const onIOSPickerChange = (_event: DateTimePickerEvent, date?: Date) => {
    if (date) setIOSPendingTime(date);
  };

  return (
    <AppScreen
      title="Log intake"
      subtitle="Capture caffeine quickly."
    >
      <SectionTitle>Quick actions</SectionTitle>
      <SectionCard>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
          {[
            ['Espresso', 60],
            ['Drip', 95],
            ['Tea', 40],
            ['Energy', 160],
          ].map(([label, amount]) => (
            <Button
              key={label}
              title={`${label} ${amount}mg`}
              variant="secondary"
              onPress={() => commitDose(amount as number, label as string)}
            />
          ))}
        </View>
      </SectionCard>

      <SectionTitle>Custom entry</SectionTitle>
      <SectionCard>
        <FormField
          label="Amount"
          footer="Use the stepper for common adjustments or type a precise amount."
        >
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
            <Button
              title="−"
              variant="outline"
              onPress={() => setMg((value) => Math.max(1, value - 10))}
            />
            <View style={{ flex: 1 }}>
              <FieldInput
                value={String(mg)}
                onChangeText={(value) => setMg(Math.max(0, parseInt(value || '0', 10)))}
                keyboardType="number-pad"
              />
            </View>
            <Button
              title="+"
              variant="outline"
              onPress={() => setMg((value) => Math.min(2000, value + 10))}
            />
          </View>
        </FormField>

        <FormField label="Source">
          <SegmentedControl
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
        </FormField>

        <FormField label="Time">
          <View style={{ flexDirection: 'row', gap: 10 }}>
            <View style={{ flex: 1 }}>
              <Button
                title={fmtTime(timestamp)}
                variant="outline"
                onPress={openTimePicker}
              />
            </View>
            <Button
              title="Now"
              variant="secondary"
              onPress={() => setTimestamp(Date.now())}
            />
          </View>
        </FormField>

        <FormField
          label="Note"
          footer="Optional context for what you drank or why."
        >
          <FieldInput
            value={note}
            onChangeText={setNote}
            placeholder="Double shot, pre-workout, after lunch..."
            multiline
          />
        </FormField>

        <View style={{ flexDirection: 'row', gap: 10 }}>
          <Button
            title="Reset"
            variant="outline"
            onPress={reset}
            style={{ flex: 1 }}
          />
          <Button
            title="Save intake"
            variant="primary"
            onPress={() => {
              if (canSave) void commitDose(mg);
            }}
            disabled={!canSave}
            style={{ flex: 1 }}
          />
        </View>
      </SectionCard>

      <Modal
        animationType="fade"
        transparent
        visible={iosPickerVisible}
        onRequestClose={() => setIOSPickerVisible(false)}
      >
        <View
          style={{
            flex: 1,
            justifyContent: 'flex-end',
            backgroundColor: palette.modalScrim,
          }}
        >
          <View
            style={{
              backgroundColor: palette.modalBackground,
              borderTopLeftRadius: 22,
              borderTopRightRadius: 22,
              paddingHorizontal: 16,
              paddingTop: 12,
              paddingBottom: 16,
              gap: 12,
            }}
          >
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Button
                title="Cancel"
                variant="plain"
                onPress={() => setIOSPickerVisible(false)}
              />
              <Button
                title="Done"
                variant="plain"
                onPress={() => {
                  setTimestamp(iosPendingTime.getTime());
                  setIOSPickerVisible(false);
                }}
              />
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
    </AppScreen>
  );
}
