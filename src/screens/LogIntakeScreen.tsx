import React, { useMemo, useRef, useState } from 'react';
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
import {
  HealthOptionCard,
  ListRow,
  SectionCard,
  SectionHeader,
  SegmentedControl,
} from '~/components/ui';
import {
  buildCustomDose,
  createCustomDoseDraft,
  getRemainingDailyCaffeineLimit,
  getTodayCaffeineTotal,
  validateCustomDoseDraft,
} from '~/features/caffeine/logging';
import { favoriteDrinks, localDayKey } from '~/features/caffeine/upgrades';
import {
  DosePreview,
  DoseUndoNotice,
  QuickDoseSheet,
  ServingCalculator,
} from '~/features/caffeine/LoggingTools';
import useNow from '~/hooks/useNow';
import {
  AppWalkthroughCoach,
  useAppWalkthrough,
  WalkthroughReveal,
} from '~/features/appWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useAppScheme from '~/hooks/useAppScheme';
import useReduceMotion from '~/hooks/useReduceMotion';
import { navigate } from '~/navigation';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { controlSizes, radii, spacing, typeRamp } from '~/theme/tokens';

const SOURCE_OPTIONS = [
  'Espresso',
  'Drip',
  'Cold Brew',
  'Tea',
  'Matcha',
  'Other',
] as const;

function makeDoseId() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

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

function fmtDateTime(timestamp: number) {
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
  const layout = useAdaptiveLayout();
  const palette = getAppPalette(useAppScheme());
  const doses = useStore((state) => state.doses);
  const dailyLimitMg = useStore((state) => state.prefs.dailyLimitMg ?? 400);
  const addDose = useStore((state) => state.addDose);
  const [customVisible, setCustomVisible] = useState(false);
  const caffeine = useStore((s) => s.caffeine);
  const savedDraft = caffeine.draft;
  const draft = savedDraft ?? createCustomDoseDraft(Date.now());
  const persistDraft = useStore((s) => s.setCaffeineDraft);
  const setDraft = (
    update: typeof draft | ((current: typeof draft) => typeof draft),
  ) => persistDraft(typeof update === 'function' ? update(draft) : update);
  const quickRefs = useRef(new Map<string, React.RefObject<View | null>>());
  const [quickFocus, setQuickFocus] = useState<React.RefObject<View | null>>();
  const [quickDrink, setQuickDrink] = useState<{
    label: string;
    mg: number;
  } | null>(null);
  const [calculatorVisible, setCalculatorVisible] = useState(false);
  const [pickerVisible, setPickerVisible] = useState(false);
  const [pendingTime, setPendingTime] = useState(() => new Date(Date.now()));
  const [confirmation, setConfirmation] = useState('');
  const reduceMotion = useReduceMotion();
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

  const now = useNow();
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

  const openCustomEntry = (triggerRef = customEntryRef) => {
    if (!savedDraft) persistDraft(createCustomDoseDraft(Date.now()));
    returnFocusRef.current = triggerRef;
    setConfirmation('');
    setPendingTime(new Date(draft.timestamp));
    setCustomVisible(true);
  };

  const saveCustomEntry = () => {
    const savedNow = Date.now();
    if (!validateCustomDoseDraft(draft, savedNow).valid) return;
    if (draft.editingId) {
      if (
        !doses.some(
          (d) => d.id === draft.editingId && !d.id.startsWith('demo:'),
        )
      ) {
        setConfirmation(
          'The original entry was removed. Discard this draft to start another entry.',
        );
        return;
      }
      const { id: _id, ...patch } = buildCustomDose(draft, makeDoseId);
      useStore.getState().updateDose(draft.editingId, patch);
    } else addDose(buildCustomDose(draft, makeDoseId));
    setCustomVisible(false);
    setPickerVisible(false);
    persistDraft(null);
    announceSaved();
  };

  const todayCard = (
    <SectionCard style={{ borderRadius: radii.hero, padding: spacing.lg }}>
      <Text style={{ ...typeRamp.headline, color: palette.textSecondary }}>
        Caffeine Today
      </Text>
      <Text
        style={{
          ...typeRamp.largeTitle,
          fontVariant: ['tabular-nums'],
          color: palette.textPrimary,
        }}
      >
        {todayTotal} mg
      </Text>
      <Text style={{ ...typeRamp.subheadline, color: palette.textSecondary }}>
        {remaining} mg remaining of {dailyLimitMg} mg
      </Text>
      <Button
        title={
          caffeine.zeroDays.includes(localDayKey(now))
            ? 'Remove caffeine-free confirmation'
            : 'Mark today caffeine-free'
        }
        variant="plain"
        disabled={doses.some(
          (d) =>
            !d.id.startsWith('demo:') &&
            localDayKey(d.timestamp) === localDayKey(now),
        )}
        onPress={() =>
          caffeine.zeroDays.includes(localDayKey(now))
            ? useStore.getState().clearCaffeineFree(now)
            : useStore.getState().markCaffeineFree(now)
        }
      />
      {caffeine.zeroDays.includes(localDayKey(now)) && (
        <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>
          Today is confirmed caffeine-free.
        </Text>
      )}
    </SectionCard>
  );

  const quickAdd = (
    <View style={{ gap: spacing.sm }}>
      <SectionHeader title="Quick Add" />
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}>
        {favoriteDrinks(caffeine).map((preset) => {
          if (!quickRefs.current.has(preset.id))
            quickRefs.current.set(preset.id, React.createRef<View>());
          const triggerRef = quickRefs.current.get(preset.id)!;
          return (
            <View
              key={preset.id}
              style={{ width: layout.isWideLayout ? '47%' : '48%' }}
            >
              <HealthOptionCard
                triggerRef={triggerRef}
                icon={preset.id === 'energy' ? 'flash' : 'cafe'}
                symbol={preset.symbol}
                title={preset.label}
                subtitle={`${preset.mg} mg`}
                accessibilityLabel={`${preset.label} ${preset.mg} mg`}
                onPress={() => {
                  setQuickFocus(triggerRef);
                  setQuickDrink(preset);
                }}
              />
            </View>
          );
        })}
      </View>
    </View>
  );

  const details = (
    <View style={{ gap: spacing.sm }}>
      <SectionHeader title="Add Details" />
      <HealthGroupedList
        rows={[
          {
            title: 'Custom Entry',
            subtitle: savedDraft
              ? 'Resume unfinished entry'
              : 'Amount, source, time, and note',
            ref: customEntryRef,
            onPress: () => openCustomEntry(customEntryRef),
          },
          {
            title: 'Drink Library & Favorites',
            onPress: () => navigate('DrinkLibrary'),
          },
          {
            title: 'Show All Caffeine Data',
            onPress: () => navigate('CaffeineHistory'),
          },
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
      trailing={
        <Button
          ref={addDataRef}
          title="Add Data"
          variant="plain"
          onPress={() => openCustomEntry(addDataRef)}
        />
      }
      scrollRef={scrollRef}
      contentRef={contentRef}
      scrollEnabled={!walkthrough.active}
      interactionEnabled={!walkthrough.active}
      bottomOverlay={walkthrough.active ? walkthroughCoach : <DoseUndoNotice />}
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
        style={
          layout.isWideLayout
            ? {
                flexDirection: 'row',
                alignItems: 'flex-start',
                gap: spacing.xl,
              }
            : { gap: spacing.md }
        }
      >
        <View
          testID="log-primary-column"
          style={{
            width: layout.isWideLayout ? layout.leftColumnWidth : '100%',
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
            width: layout.isWideLayout ? layout.rightColumnWidth : '100%',
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
              onLayout={() =>
                walkthrough.measureAnchor(
                  'log-details',
                  detailsAnchorRef.current,
                )
              }
              style={{ gap: spacing.md }}
            >
              <View style={{ gap: spacing.sm }}>
                <SectionHeader title="Recent" />
                <SectionCard>
                  {recent.length ? (
                    recent.map((dose) => (
                      <ListRow
                        key={dose.id}
                        title={`${dose.mg} mg${dose.source ? ` • ${dose.source}` : ''}`}
                        subtitle={fmtDateTime(dose.timestamp)}
                      />
                    ))
                  ) : (
                    <Text
                      style={{
                        ...typeRamp.subheadline,
                        color: palette.textSecondary,
                      }}
                    >
                      No caffeine logged yet.
                    </Text>
                  )}
                </SectionCard>
              </View>
              {details}
            </View>
          </WalkthroughReveal>
        </View>
      </View>

      <QuickDoseSheet
        returnFocusRef={quickFocus}
        onSaved={announceSaved}
        drink={quickDrink}
        onClose={() => {
          setQuickDrink(null);
        }}
      />
      {confirmation ? (
        <Text
          accessibilityLiveRegion="polite"
          accessibilityLabel={confirmation}
          style={{ ...typeRamp.subheadline, color: palette.statusSuccessText }}
        >
          {confirmation}
        </Text>
      ) : null}

      <HealthFormSheet
        visible={customVisible && !walkthrough.active}
        title={draft.editingId ? 'Edit Entry' : 'Custom Entry'}
        returnFocusRef={returnFocusRef.current}
        onCancel={() => {
          setPickerVisible(false);
          setCustomVisible(false);
        }}
        onSave={saveCustomEntry}
        saveDisabled={!validation.valid || walkthrough.active}
        reduceMotion={reduceMotion}
      >
        <View style={{ gap: spacing.sm }}>
          <TextInput
            accessibilityLabel="Amount"
            value={draft.mg}
            onChangeText={(mg) => setDraft((current) => ({ ...current, mg }))}
            keyboardType="number-pad"
            placeholder="Amount in mg"
            style={{
              minHeight: controlSizes.inputHeight,
              borderRadius: radii.control,
              paddingHorizontal: spacing.sm,
              backgroundColor: palette.fieldBackground,
              color: palette.textPrimary,
              ...typeRamp.body,
            }}
          />
          <TextInput
            accessibilityLabel="Drink name or source"
            value={draft.source}
            onChangeText={(source) =>
              setDraft((current) => ({ ...current, source }))
            }
            placeholder="Drink name or source"
            style={{
              minHeight: controlSizes.inputHeight,
              borderRadius: radii.control,
              paddingHorizontal: spacing.sm,
              backgroundColor: palette.fieldBackground,
              color: palette.textPrimary,
              ...typeRamp.body,
            }}
          />
          <SegmentedControl
            value={draft.source}
            onChange={(source) =>
              setDraft((current) => ({ ...current, source }))
            }
            options={SOURCE_OPTIONS.map((source) => ({
              key: source,
              label: source,
            }))}
          />
          <Button
            title={fmtTime(draft.timestamp)}
            accessibilityLabel="Time"
            accessibilityValue={{ text: fmtTime(draft.timestamp) }}
            variant="tinted"
            onPress={() => {
              setPendingTime(new Date(draft.timestamp));
              setPickerVisible(true);
            }}
          />
          <TextInput
            accessibilityLabel="Note"
            value={draft.note}
            onChangeText={(note) =>
              setDraft((current) => ({ ...current, note }))
            }
            placeholder="Optional note"
            multiline
            style={{
              minHeight: 96,
              borderRadius: radii.control,
              padding: spacing.sm,
              backgroundColor: palette.fieldBackground,
              color: palette.textPrimary,
              ...typeRamp.body,
            }}
          />
          <Button
            title={calculatorVisible ? 'Hide calculator' : 'Serving calculator'}
            variant="plain"
            onPress={() => setCalculatorVisible(!calculatorVisible)}
          />
          {calculatorVisible && (
            <ServingCalculator
              onApply={(mg) => {
                setDraft((current) => ({ ...current, mg: String(mg) }));
                setCalculatorVisible(false);
              }}
            />
          )}
          {validation.valid && (
            <DosePreview draft={draft} replacingId={draft.editingId} />
          )}
          <Button
            title="Discard unfinished entry"
            variant="plain"
            role="destructive"
            onPress={() => {
              persistDraft(null);
              setCustomVisible(false);
              setPickerVisible(false);
            }}
          />
          {!validation.valid ? (
            <Text style={{ ...typeRamp.footnote, color: palette.destructive }}>
              {validation.message}
            </Text>
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
        <View
          accessibilityViewIsModal
          style={{
            flex: 1,
            justifyContent: 'flex-end',
            backgroundColor: palette.modalScrim,
          }}
        >
          <View
            style={{
              backgroundColor: palette.modalBackground,
              padding: spacing.md,
              gap: spacing.sm,
            }}
          >
            <View
              style={{ flexDirection: 'row', justifyContent: 'space-between' }}
            >
              <Button
                title="Cancel"
                variant="plain"
                onPress={() => setPickerVisible(false)}
              />
              <Button
                title="Done"
                variant="plain"
                onPress={() => {
                  setDraft((current) => ({
                    ...current,
                    timestamp: pendingTime.getTime(),
                  }));
                  setPickerVisible(false);
                }}
              />
            </View>
            <DateTimePicker
              testID="caffeine-time-picker"
              mode="time"
              display="spinner"
              value={pendingTime}
              onChange={(_event: DateTimePickerEvent, date?: Date) => {
                if (date) setPendingTime(date);
              }}
            />
          </View>
        </View>
      </Modal>
    </AppScreen>
  );
}
