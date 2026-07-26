import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Modal,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';
import DateTimePicker, {
  DateTimePickerEvent,
} from '@react-native-community/datetimepicker';
import * as Haptics from 'expo-haptics';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { HealthFormSheet, HealthGroupedList } from '~/components/health';
import { HealthOptionCard, ListRow, SectionCard, SectionHeader, SegmentedControl } from '~/components/ui';
import {
  buildCustomDose,
  buildQuickAddDose,
  createCustomDoseDraft,
  getRemainingDailyCaffeineLimit,
  getTodayCaffeineTotal,
  validateCustomDoseDraft,
} from '~/features/caffeine/logging';
import { CAFFEINE_PRESETS } from '~/features/caffeine/presets';
import {
  AppWalkthroughCoach,
  useAppWalkthrough,
  WalkthroughReveal,
} from '~/features/appWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useAppScheme from '~/hooks/useAppScheme';
import { navigate } from '~/navigation';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { controlSizes, radii, spacing, typeRamp } from '~/theme/tokens';

const SOURCE_OPTIONS = ['Espresso', 'Drip', 'Cold Brew', 'Tea', 'Matcha', 'Other'] as const;

function makeDoseId() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

function fmtTime(timestamp: number) {
  try {
    return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toLocaleTimeString();
  }
}

function fmtDateTime(timestamp: number) {
  try {
    return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toLocaleTimeString();
  }
}

export default function LogIntakeScreen() {
  const layout = useAdaptiveLayout();
  const palette = getAppPalette(useAppScheme());
  const doses = useStore((state) => state.doses);
  const dailyLimitMg = useStore((state) => state.prefs.dailyLimitMg ?? 400);
  const addDose = useStore((state) => state.addDose);
  const [customVisible, setCustomVisible] = useState(false);
  const [draft, setDraft] = useState(() => createCustomDoseDraft(Date.now()));
  const [pickerVisible, setPickerVisible] = useState(false);
  const [pendingTime, setPendingTime] = useState(() => new Date(Date.now()));
  const [confirmation, setConfirmation] = useState('');
  const [reduceMotion, setReduceMotion] = useState(true);
  const addDataRef = useRef<View>(null);
  const customEntryRef = useRef<View>(null);
  const returnFocusRef = useRef(addDataRef);
  const scrollRef = useRef<ScrollView>(null);
  const contentRef = useRef<View>(null);
  const detailsAnchorRef = useRef<View>(null);
  const walkthrough = useAppWalkthrough({
    route: 'Log',
    isWideLayout: layout.isWideLayout,
    scrollRef,
    contentRef,
  });

  useEffect(() => {
    let alive = true;
    let receivedSystemEvent = false;
    const onReduceMotionChanged = (enabled: boolean) => {
      receivedSystemEvent = true;
      if (alive) setReduceMotion(enabled);
    };

    AccessibilityInfo.isReduceMotionEnabled()
      .then((enabled) => {
        if (alive && !receivedSystemEvent) setReduceMotion(enabled);
      })
      .catch(() => {
        if (alive && !receivedSystemEvent) setReduceMotion(true);
      });
    const subscription = AccessibilityInfo.addEventListener(
      'reduceMotionChanged',
      onReduceMotionChanged,
    );
    return () => {
      alive = false;
      subscription.remove();
    };
  }, []);

  const now = Date.now();
  const validation = validateCustomDoseDraft(draft, now);
  const todayTotal = getTodayCaffeineTotal(doses, now);
  const remaining = getRemainingDailyCaffeineLimit(doses, now, dailyLimitMg);
  const recent = useMemo(
    () => [...doses].sort((a, b) => b.timestamp - a.timestamp).slice(0, 4),
    [doses],
  );

  const announceSaved = () => {
    setConfirmation('Caffeine intake saved.');
    AccessibilityInfo.announceForAccessibility('Caffeine intake saved.');
    if (!reduceMotion) {
      void Haptics.notificationAsync(
        Haptics.NotificationFeedbackType.Success,
      ).catch(() => undefined);
    }
  };

  const saveQuickAdd = (preset: (typeof CAFFEINE_PRESETS)[number]) => {
    const savedNow = Date.now();
    if (!reduceMotion) {
      void Haptics.impactAsync(
        Haptics.ImpactFeedbackStyle.Light,
      ).catch(() => undefined);
    }
    addDose(buildQuickAddDose(preset, savedNow, makeDoseId));
    announceSaved();
  };

  const openCustomEntry = (triggerRef = customEntryRef) => {
    returnFocusRef.current = triggerRef;
    setConfirmation('');
    setPendingTime(new Date(draft.timestamp));
    setCustomVisible(true);
  };

  const saveCustomEntry = () => {
    const savedNow = Date.now();
    if (!validateCustomDoseDraft(draft, savedNow).valid) return;
    addDose(buildCustomDose(draft, makeDoseId));
    setCustomVisible(false);
    setPickerVisible(false);
    setDraft(createCustomDoseDraft(savedNow));
    announceSaved();
  };

  const todayCard = (
    <SectionCard style={{ borderRadius: radii.hero, padding: spacing.lg }}>
      <Text style={{ ...typeRamp.headline, color: palette.textSecondary }}>Caffeine Today</Text>
      <Text style={{ ...typeRamp.largeTitle, fontVariant: ['tabular-nums'], color: palette.textPrimary }}>
        {todayTotal} mg
      </Text>
      <Text style={{ ...typeRamp.subheadline, color: palette.textSecondary }}>
        {remaining} mg remaining of {dailyLimitMg} mg
      </Text>
    </SectionCard>
  );

  const quickAdd = (
    <View style={{ gap: spacing.sm }}>
      <SectionHeader title="Quick Add" />
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}>
        {CAFFEINE_PRESETS.map((preset) => (
          <View key={preset.id} style={{ width: layout.isWideLayout ? '47%' : '48%' }}>
            <HealthOptionCard
              icon={preset.id === 'energy' ? 'flash' : 'cafe'}
              symbol={preset.symbol}
              title={preset.label}
              subtitle={`${preset.mg} mg`}
              accessibilityLabel={`${preset.label} ${preset.mg} mg`}
              onPress={() => saveQuickAdd(preset)}
            />
          </View>
        ))}
      </View>
    </View>
  );

  const details = (
    <View style={{ gap: spacing.sm }}>
      <SectionHeader title="Add Details" />
      <HealthGroupedList
        rows={[
          { title: 'Custom Entry', subtitle: 'Amount, source, time, and note', ref: customEntryRef, onPress: () => openCustomEntry(customEntryRef) },
          { title: 'Show All Caffeine Data', onPress: () => navigate('CaffeineHistory') },
        ]}
      />
    </View>
  );

  const walkthroughCoach = walkthrough.active ? (
    <WalkthroughReveal
      key={walkthrough.step.id}
      active
      revealed={walkthrough.coachVisible}
      reduceMotion={walkthrough.reduceMotion}
    >
      <AppWalkthroughCoach
        step={walkthrough.step}
        locked={walkthrough.locked}
        headingRef={walkthrough.coachHeadingRef}
        onLayout={walkthrough.onCoachLayout}
        onSkip={walkthrough.onSkip}
        onPrimary={walkthrough.onPrimary}
      />
    </WalkthroughReveal>
  ) : null;

  return (
    <AppScreen
      title="Log"
      trailing={<Button ref={addDataRef} title="Add Data" variant="plain" onPress={() => openCustomEntry(addDataRef)} />}
      scrollRef={scrollRef}
      contentRef={contentRef}
      scrollEnabled={!walkthrough.active}
      interactionEnabled={!walkthrough.active}
      bottomOverlay={walkthroughCoach}
      onScroll={walkthrough.onScroll}
      onViewportLayout={walkthrough.onViewportLayout}
      headerTransform={(header) => (
        <WalkthroughReveal
          active={walkthrough.active}
          revealed={walkthrough.isRevealed('log-header')}
          reduceMotion={walkthrough.reduceMotion}
        >
          {header}
        </WalkthroughReveal>
      )}
    >
      <View
        testID={layout.isWideLayout ? 'log-wide-layout' : 'log-compact-layout'}
        style={layout.isWideLayout ? { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.xl } : { gap: spacing.md }}
      >
        <View
          testID="log-primary-column"
          style={{
            width: layout.isWideLayout
              ? layout.leftColumnWidth
              : '100%',
            gap: spacing.md,
          }}
        >
          <WalkthroughReveal
            active={walkthrough.active}
            revealed={walkthrough.isRevealed('log-quick-add')}
            reduceMotion={walkthrough.reduceMotion}
            style={{ gap: spacing.md }}
          >
            {todayCard}
            {quickAdd}
          </WalkthroughReveal>
        </View>
        <View
          testID="log-supporting-column"
          style={{
            width: layout.isWideLayout
              ? layout.rightColumnWidth
              : '100%',
            gap: spacing.md,
          }}
        >
          <WalkthroughReveal
            active={walkthrough.active}
            revealed={walkthrough.isRevealed('log-details')}
            reduceMotion={walkthrough.reduceMotion}
          >
            <View
              ref={detailsAnchorRef}
              collapsable={false}
              onLayout={() => walkthrough.measureAnchor('log-details', detailsAnchorRef.current)}
              style={{ gap: spacing.md }}
            >
              <View style={{ gap: spacing.sm }}>
                <SectionHeader title="Recent" />
                <SectionCard>
                  {recent.length ? recent.map((dose) => (
                    <ListRow key={dose.id} title={`${dose.mg} mg${dose.source ? ` • ${dose.source}` : ''}`} subtitle={fmtDateTime(dose.timestamp)} />
                  )) : (
                    <Text style={{ ...typeRamp.subheadline, color: palette.textSecondary }}>No caffeine logged yet.</Text>
                  )}
                </SectionCard>
              </View>
              {details}
            </View>
          </WalkthroughReveal>
        </View>
      </View>

      {confirmation ? (
        <Text accessibilityLiveRegion="polite" accessibilityLabel={confirmation} style={{ ...typeRamp.subheadline, color: palette.statusSuccessText }}>
          {confirmation}
        </Text>
      ) : null}

      <HealthFormSheet
        visible={customVisible}
        title="Custom Entry"
        returnFocusRef={returnFocusRef.current}
        onCancel={() => { setPickerVisible(false); setCustomVisible(false); }}
        onSave={saveCustomEntry}
        saveDisabled={!validation.valid}
        reduceMotion={reduceMotion}
      >
        <View style={{ gap: spacing.sm }}>
          <TextInput
            accessibilityLabel="Amount"
            value={draft.mg}
            onChangeText={(mg) => setDraft((current) => ({ ...current, mg }))}
            keyboardType="number-pad"
            placeholder="Amount in mg"
            style={{ minHeight: controlSizes.inputHeight, borderRadius: radii.control, paddingHorizontal: spacing.sm, backgroundColor: palette.fieldBackground, color: palette.textPrimary, ...typeRamp.body }}
          />
          <SegmentedControl
            value={draft.source}
            onChange={(source) => setDraft((current) => ({ ...current, source }))}
            options={SOURCE_OPTIONS.map((source) => ({ key: source, label: source }))}
          />
          <Button
            title={fmtTime(draft.timestamp)}
            accessibilityLabel="Time"
            accessibilityValue={{ text: fmtTime(draft.timestamp) }}
            variant="tinted"
            onPress={() => { setPendingTime(new Date(draft.timestamp)); setPickerVisible(true); }}
          />
          <TextInput
            accessibilityLabel="Note"
            value={draft.note}
            onChangeText={(note) => setDraft((current) => ({ ...current, note }))}
            placeholder="Optional note"
            multiline
            style={{ minHeight: 96, borderRadius: radii.control, padding: spacing.sm, backgroundColor: palette.fieldBackground, color: palette.textPrimary, ...typeRamp.body }}
          />
          {!validation.valid ? (
            <Text style={{ ...typeRamp.footnote, color: palette.destructive }}>{validation.message}</Text>
          ) : null}
        </View>
      </HealthFormSheet>

      <Modal
        testID="caffeine-time-picker-modal"
        transparent
        visible={pickerVisible}
        animationType={reduceMotion ? 'none' : 'fade'}
        onRequestClose={() => setPickerVisible(false)}
      >
        <View accessibilityViewIsModal style={{ flex: 1, justifyContent: 'flex-end', backgroundColor: palette.modalScrim }}>
          <View style={{ backgroundColor: palette.modalBackground, padding: spacing.md, gap: spacing.sm }}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Button title="Cancel" variant="plain" onPress={() => setPickerVisible(false)} />
              <Button title="Done" variant="plain" onPress={() => { setDraft((current) => ({ ...current, timestamp: pendingTime.getTime() })); setPickerVisible(false); }} />
            </View>
            <DateTimePicker
              testID="caffeine-time-picker"
              mode="time"
              display="spinner"
              value={pendingTime}
              onChange={(_event: DateTimePickerEvent, date?: Date) => { if (date) setPendingTime(date); }}
            />
          </View>
        </View>
      </Modal>
    </AppScreen>
  );
}
