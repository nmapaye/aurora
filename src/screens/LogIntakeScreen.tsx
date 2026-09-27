import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { RefObject } from 'react';
import {
  AccessibilityInfo,
  Alert,
  Modal,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';
import DateTimePicker, {
  DateTimePickerEvent,
} from '@react-native-community/datetimepicker';
import { haptics } from '~/services/platform/haptics';

import AppScreen from '~/components/AppScreen';
import AppSymbol, { type AppSymbolFallbackName } from '~/components/AppSymbol';
import Button from '~/components/Button';
import { HealthFormSheet, HealthGroupedList } from '~/components/health';
import { SectionCard, SectionHeader, SegmentedControl } from '~/components/ui';
import type { Dose } from '~/domain/models';
import {
  buildCustomDose,
  buildDosePatch,
  buildQuickAddDose,
  createCustomDoseDraft,
  createDoseId,
  createEditDoseDraft,
  type CustomDoseDraft,
  validateCustomDoseDraft,
} from '~/features/caffeine/logging';
import { CAFFEINE_PRESETS, type CaffeinePreset } from '~/features/caffeine/presets';
import {
  acceptsQuickAdd,
  describeDose,
  displayDoseNote,
  doseSourceLabel,
  formatDoseDateTime,
  formatDoseTitle,
  getLoggedTodaySummary,
  getRecentDoses,
  isEditableDose,
  quickAddConfirmation,
} from '~/features/caffeine/presentation';
import {
  AppWalkthroughCoach,
  useAppWalkthrough,
  WalkthroughReveal,
} from '~/features/appWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useNow from '~/hooks/useNow';
import useAppScheme from '~/hooks/useAppScheme';
import useLargeText from '~/hooks/useLargeText';
import useReduceMotion from '~/hooks/useReduceMotion';
import { navigate } from '~/navigation';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import {
  borders,
  controlSizes,
  fontScaling,
  iconSizes,
  numericText,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';

const SOURCE_OPTIONS = ['Espresso', 'Drip', 'Cold Brew', 'Tea', 'Matcha', 'Other'] as const;

const PRESET_FALLBACK_ICONS: Record<CaffeinePreset['id'], AppSymbolFallbackName> = {
  espresso: 'cafe',
  drip: 'cafe',
  matcha: 'leaf',
  energy: 'flash',
};

// A just-logged quick add stays undoable until the next logging action.
type Feedback = { message: string; undoDoseId?: string };

function PresetTile({
  preset,
  fullWidth,
  onPress,
}: {
  preset: CaffeinePreset;
  fullWidth: boolean;
  onPress: () => void;
}) {
  const palette = getAppPalette(useAppScheme());
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Log ${preset.label}, ${preset.mg} mg`}
      accessibilityHint="Adds an entry at the current time. Undo appears after logging."
      onPress={onPress}
      style={({ pressed }) => ({
        width: fullWidth ? '100%' : '48%',
        flexGrow: 1,
        minHeight: controlSizes.minimumTouchTarget + spacing.lg,
        flexDirection: 'row',
        alignItems: 'center',
        gap: spacing.sm,
        paddingHorizontal: spacing.md,
        paddingVertical: spacing.sm,
        borderRadius: radii.card,
        borderWidth: borders.hairline,
        borderColor: palette.cardBorder,
        backgroundColor: pressed ? palette.pressed : palette.card,
        transform: [{ scale: pressed ? 0.98 : 1 }],
      })}
    >
      <AppSymbol
        name={preset.symbol}
        fallback={PRESET_FALLBACK_ICONS[preset.id]}
        size={iconSizes.button}
        tintColor={palette.tint}
      />
      <View style={{ flex: 1, gap: 2 }}>
        <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.headline, color: palette.textPrimary }}>
          {preset.label}
        </Text>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.subheadline, fontVariant: ['tabular-nums'], color: palette.textSecondary }}
        >
          {preset.mg} mg
        </Text>
      </View>
      <AppSymbol name="plus.circle.fill" fallback="add-circle" size={iconSizes.row} tintColor={palette.tint} />
    </Pressable>
  );
}

function RecentDoseRow({
  dose,
  first,
  largeText,
  rowRef,
  onEdit,
}: {
  dose: Dose;
  first: boolean;
  largeText: boolean;
  rowRef: RefObject<View | null>;
  onEdit: () => void;
}) {
  const palette = getAppPalette(useAppScheme());
  const editable = isEditableDose(dose);
  const source = doseSourceLabel(dose);
  const note = displayDoseNote(dose);
  const content = (
    <View
      style={{
        minHeight: controlSizes.minimumTouchTarget + spacing.xs,
        flexDirection: largeText ? 'column' : 'row',
        alignItems: largeText ? 'flex-start' : 'center',
        gap: largeText ? spacing.xxs : spacing.sm,
        paddingHorizontal: spacing.md,
        paddingVertical: spacing.xs,
        borderTopWidth: first ? 0 : borders.hairline,
        borderColor: palette.separator,
      }}
    >
      <View style={{ flex: largeText ? undefined : 1, gap: spacing.xxs }}>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.body, fontVariant: ['tabular-nums'], color: palette.textPrimary }}
        >
          {formatDoseTitle(dose)}
        </Text>
        <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.footnote, color: palette.textSecondary }}>
          {formatDoseDateTime(dose.timestamp)}
        </Text>
        {note ? (
          <Text
            numberOfLines={2}
            maxFontSizeMultiplier={fontScaling.body}
            style={{ ...typeRamp.footnote, color: palette.textTertiary }}
          >
            {note}
          </Text>
        ) : null}
      </View>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xxs }}>
        {/* Status text, not an action: read-only rows stay quieter than editable ones. */}
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.footnote, color: editable ? palette.textSecondary : palette.textTertiary }}
        >
          {editable ? `${source} · Edit` : `${source} · Read-only`}
        </Text>
        {editable ? (
          <AppSymbol name="chevron.forward" fallback="chevron-forward" size={iconSizes.inline} tintColor={palette.textTertiary} />
        ) : null}
      </View>
    </View>
  );

  if (!editable) {
    return (
      <View accessible accessibilityLabel={describeDose(dose)}>
        {content}
      </View>
    );
  }
  return (
    <Pressable
      ref={rowRef}
      accessibilityRole="button"
      accessibilityLabel={describeDose(dose)}
      accessibilityHint="Opens the entry to correct or delete it."
      onPress={onEdit}
      style={({ pressed }) => ({ backgroundColor: pressed ? palette.pressed : 'transparent' })}
    >
      {content}
    </Pressable>
  );
}

export default function LogIntakeScreen() {
  const layout = useAdaptiveLayout();
  const palette = getAppPalette(useAppScheme());
  const largeText = useLargeText();
  const doses = useStore((state) => state.doses);
  const addDose = useStore((state) => state.addDose);
  const updateDose = useStore((state) => state.updateDose);
  const removeDose = useStore((state) => state.removeDose);
  const [sheetVisible, setSheetVisible] = useState(false);
  // null while adding a new entry; the entry's id while correcting one.
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draft, setDraft] = useState(() => createCustomDoseDraft(Date.now()));
  // The new-entry time follows the clock until the user picks one.
  const [draftTimeChosen, setDraftTimeChosen] = useState(false);
  const [editDraft, setEditDraft] = useState<CustomDoseDraft>(() => createCustomDoseDraft(Date.now()));
  const [pickerVisible, setPickerVisible] = useState(false);
  const [pendingTime, setPendingTime] = useState(() => new Date(Date.now()));
  const [feedback, setFeedback] = useState<Feedback | null>(null);
  const lastQuickAddAtRef = useRef<number | undefined>(undefined);
  const reduceMotion = useReduceMotion();
  const customEntryRef = useRef<View>(null);
  const recentHeaderRef = useRef<View>(null);
  const rowRefs = useRef(new Map<string, RefObject<View | null>>());
  const [returnFocusRef, setReturnFocusRef] = useState<RefObject<View | null>>(customEntryRef);
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
  const editing = editingId !== null;
  const editingDose = editing ? doses.find((dose) => dose.id === editingId) : undefined;
  const activeDraft = editing ? editDraft : draft;
  const setActiveDraft = editing ? setEditDraft : setDraft;
  // Validation uses the live clock: the shared minute clock can lag a fresh draft.
  const validation = validateCustomDoseDraft(activeDraft, Date.now());
  const today = getLoggedTodaySummary(doses, now);
  const recent = useMemo(() => getRecentDoses(doses), [doses]);
  const sourceOptions = activeDraft.source && !(SOURCE_OPTIONS as readonly string[]).includes(activeDraft.source)
    ? [...SOURCE_OPTIONS, activeDraft.source]
    : [...SOURCE_OPTIONS];

  const rowRef = (id: string) => {
    let ref = rowRefs.current.get(id);
    if (!ref) {
      ref = { current: null };
      rowRefs.current.set(id, ref);
    }
    return ref;
  };

  const announce = (message: string, undoDoseId?: string) => {
    setFeedback({ message, undoDoseId });
    AccessibilityInfo.announceForAccessibility(
      undoDoseId ? `${message} Undo is available.` : message,
    );
  };

  const closeSheet = () => {
    setPickerVisible(false);
    setSheetVisible(false);
    setEditingId(null);
  };

  // An entry removed elsewhere (History, Sample Data) cannot stay open here.
  useEffect(() => {
    if (editingId === null || editingDose) return;
    setPickerVisible(false);
    setSheetVisible(false);
    setEditingId(null);
  }, [editingDose, editingId]);

  const saveQuickAdd = (preset: CaffeinePreset) => {
    const savedNow = Date.now();
    if (!acceptsQuickAdd(lastQuickAddAtRef.current, savedNow)) return;
    lastQuickAddAtRef.current = savedNow;
    const dose = buildQuickAddDose(preset, savedNow, () => createDoseId());
    addDose(dose);
    announce(quickAddConfirmation(dose), dose.id);
    haptics.success();
  };

  const undoQuickAdd = () => {
    const doseId = feedback?.undoDoseId;
    if (!doseId) return;
    const dose = useStore.getState().doses.find((item) => item.id === doseId);
    if (dose) removeDose(doseId);
    announce(dose ? `Removed ${formatDoseTitle(dose)}.` : 'That entry was already removed.');
  };

  const openCustomEntry = (triggerRef: RefObject<View | null>) => {
    setReturnFocusRef(triggerRef);
    setFeedback(null);
    setEditingId(null);
    const openTime = draftTimeChosen ? draft.timestamp : Date.now();
    if (!draftTimeChosen) setDraft((current) => ({ ...current, timestamp: openTime }));
    setPendingTime(new Date(openTime));
    setSheetVisible(true);
  };

  const openEdit = (dose: Dose) => {
    if (!isEditableDose(dose)) return;
    setReturnFocusRef(rowRef(dose.id));
    setFeedback(null);
    setEditingId(dose.id);
    setEditDraft(createEditDoseDraft(dose));
    setPendingTime(new Date(dose.timestamp));
    setSheetVisible(true);
  };

  const saveSheet = () => {
    const savedNow = Date.now();
    if (!validateCustomDoseDraft(activeDraft, savedNow).valid) return;
    if (editing) {
      if (!editingDose) return;
      updateDose(editingDose.id, buildDosePatch(editDraft));
      closeSheet();
      announce('Entry updated.');
    } else {
      addDose(buildCustomDose(draft, () => createDoseId()));
      closeSheet();
      setDraft(createCustomDoseDraft(savedNow));
      setDraftTimeChosen(false);
      announce('Caffeine intake saved.');
    }
    haptics.success();
  };

  const confirmDelete = () => {
    if (!editingDose) return;
    const target = editingDose;
    Alert.alert(
      'Delete this entry?',
      `${formatDoseTitle(target)} on ${formatDoseDateTime(target.timestamp)} will be removed from Aurora.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            haptics.warning();
            removeDose(target.id);
            // The row is gone, so focus returns to the Recent heading.
            setReturnFocusRef(recentHeaderRef);
            closeSheet();
            announce('Entry deleted.');
          },
        },
      ],
    );
  };

  const todayCard = (
    <SectionCard style={{ borderRadius: radii.hero, padding: spacing.lg }}>
      <View accessible accessibilityLabel={today.accessibilityLabel} style={{ gap: spacing.xxs }}>
        <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.headline, color: palette.textSecondary }}>
          {today.label}
        </Text>
        <Text maxFontSizeMultiplier={fontScaling.hero} style={{ ...numericText, ...typeRamp.largeTitle, color: palette.textPrimary }}>
          {today.value}
        </Text>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: spacing.xs }}>
          {today.source ? (
            <View
              style={{
                paddingHorizontal: spacing.xs,
                paddingVertical: 2,
                borderRadius: radii.capsule,
                backgroundColor: today.sample ? palette.selectionFill : 'transparent',
                borderWidth: today.sample ? 0 : borders.hairline,
                borderColor: palette.cardBorder,
              }}
            >
              <Text
                maxFontSizeMultiplier={fontScaling.body}
                style={{ ...typeRamp.caption, fontWeight: '600', color: today.sample ? palette.tint : palette.textSecondary }}
              >
                {today.source}
              </Text>
            </View>
          ) : null}
          <Text maxFontSizeMultiplier={fontScaling.body} style={{ flexShrink: 1, ...typeRamp.subheadline, color: palette.textSecondary }}>
            {today.detail}
          </Text>
        </View>
      </View>
    </SectionCard>
  );

  const feedbackBanner = feedback ? (
    <View
      style={{
        flexDirection: largeText ? 'column' : 'row',
        alignItems: largeText ? 'flex-start' : 'center',
        gap: spacing.xs,
        paddingHorizontal: spacing.md,
        paddingVertical: spacing.xs,
        borderRadius: radii.card,
        backgroundColor: palette.card,
        borderWidth: borders.hairline,
        borderColor: palette.cardBorder,
      }}
    >
      <Text
        accessibilityLiveRegion="polite"
        accessibilityLabel={feedback.message}
        maxFontSizeMultiplier={fontScaling.body}
        style={{ flex: largeText ? undefined : 1, ...typeRamp.subheadline, color: palette.statusSuccessText }}
      >
        {feedback.message}
      </Text>
      {feedback.undoDoseId ? (
        <Button title="Undo" variant="plain" accessibilityLabel="Undo last quick add" onPress={undoQuickAdd} />
      ) : null}
    </View>
  ) : null;

  const quickAdd = (
    <View style={{ gap: spacing.sm }}>
      <SectionHeader title="Quick Add" />
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}>
        {CAFFEINE_PRESETS.map((preset) => (
          <PresetTile
            key={preset.id}
            preset={preset}
            fullWidth={largeText}
            onPress={() => saveQuickAdd(preset)}
          />
        ))}
      </View>
      {feedbackBanner}
      <Button
        ref={customEntryRef}
        title="Custom Entry"
        variant="tinted"
        accessibilityLabel="Custom Entry"
        iconLeft={<AppSymbol name="square.and.pencil" fallback="create-outline" size={iconSizes.inline} tintColor={palette.tint} />}
        onPress={() => openCustomEntry(customEntryRef)}
      />
      <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.footnote, color: palette.textTertiary }}>
        Set the amount, source, date and time, and an optional note.
      </Text>
    </View>
  );

  const recentSection = (
    <View style={{ gap: spacing.sm }}>
      <View ref={recentHeaderRef} accessible accessibilityRole="header" accessibilityLabel="Recent">
        <SectionHeader title="Recent" />
      </View>
      <View
        style={{
          overflow: 'hidden',
          backgroundColor: palette.card,
          borderRadius: radii.card,
          borderWidth: borders.hairline,
          borderColor: palette.cardBorder,
        }}
      >
        {recent.length ? recent.map((dose, index) => (
          <RecentDoseRow
            key={dose.id}
            dose={dose}
            first={index === 0}
            largeText={largeText}
            rowRef={rowRef(dose.id)}
            onEdit={() => openEdit(dose)}
          />
        )) : (
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{ ...typeRamp.subheadline, color: palette.textSecondary, padding: spacing.md }}
          >
            No caffeine logged yet.
          </Text>
        )}
      </View>
      <HealthGroupedList
        rows={[
          {
            title: 'Show All Caffeine Data',
            subtitle: 'Every entry, with search and export',
            accessibilityHint: 'Opens full caffeine history',
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

  const pickerMaximum = new Date(Math.max(Date.now(), activeDraft.timestamp));

  return (
    <AppScreen
      title="Log"
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
              {recentSection}
            </View>
          </WalkthroughReveal>
        </View>
      </View>

      <HealthFormSheet
        visible={sheetVisible}
        title={editing ? 'Edit Entry' : 'Custom Entry'}
        returnFocusRef={returnFocusRef}
        onCancel={closeSheet}
        onSave={saveSheet}
        saveDisabled={!validation.valid}
        reduceMotion={reduceMotion}
      >
        <View style={{ gap: spacing.sm }}>
          <TextInput
            accessibilityLabel="Amount"
            value={activeDraft.mg}
            onChangeText={(mg) => setActiveDraft((current) => ({ ...current, mg }))}
            keyboardType="number-pad"
            placeholder="Amount in mg"
            maxFontSizeMultiplier={fontScaling.body}
            style={{ minHeight: controlSizes.inputHeight, borderRadius: radii.control, paddingHorizontal: spacing.sm, backgroundColor: palette.fieldBackground, color: palette.textPrimary, ...typeRamp.body }}
          />
          <SegmentedControl
            value={activeDraft.source}
            onChange={(source) => setActiveDraft((current) => ({ ...current, source }))}
            options={sourceOptions.map((source) => ({ key: source, label: source }))}
          />
          <Button
            title={formatDoseDateTime(activeDraft.timestamp)}
            accessibilityLabel="Date and Time"
            accessibilityValue={{ text: formatDoseDateTime(activeDraft.timestamp) }}
            variant="tinted"
            onPress={() => { setPendingTime(new Date(activeDraft.timestamp)); setPickerVisible(true); }}
          />
          <TextInput
            accessibilityLabel="Note"
            value={activeDraft.note}
            onChangeText={(note) => setActiveDraft((current) => ({ ...current, note }))}
            placeholder="Optional note"
            multiline
            maxFontSizeMultiplier={fontScaling.body}
            style={{ minHeight: 96, borderRadius: radii.control, padding: spacing.sm, backgroundColor: palette.fieldBackground, color: palette.textPrimary, ...typeRamp.body }}
          />
          {!validation.valid ? (
            <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.footnote, color: palette.destructive }}>
              {validation.message}
            </Text>
          ) : null}
          {editing ? (
            <Button
              title="Delete Entry"
              variant="plain"
              role="destructive"
              onPress={confirmDelete}
            />
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
              <Button
                title="Done"
                variant="plain"
                onPress={() => {
                  setActiveDraft((current) => ({ ...current, timestamp: pendingTime.getTime() }));
                  if (!editing) setDraftTimeChosen(true);
                  setPickerVisible(false);
                }}
              />
            </View>
            <DateTimePicker
              testID="caffeine-time-picker"
              mode="datetime"
              display="spinner"
              value={pendingTime}
              maximumDate={pickerMaximum}
              onChange={(_event: DateTimePickerEvent, date?: Date) => { if (date) setPendingTime(date); }}
            />
          </View>
        </View>
      </Modal>
    </AppScreen>
  );
}
