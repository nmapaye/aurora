import { useSafeAreaInsets } from 'react-native-safe-area-context';
import React, { useState } from 'react';
import * as Haptics from 'expo-haptics';
import { AccessibilityInfo, Text, View } from 'react-native';
import { HealthFormSheet } from '~/components/health';
import useReduceMotion from '~/hooks/useReduceMotion';
import Button from '~/components/Button';
import {
  FieldInput,
  SectionCard,
  SectionHeader,
  SegmentedControl,
} from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
import useNow from '~/hooks/useNow';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { spacing, typeRamp } from '~/theme/tokens';
import type { CustomDoseDraft } from './logging';
import {
  availableDrinks,
  calculateServing,
  nextPlannedBedtime,
  previewDose,
  type PersonalDrink,
} from './upgrades';

export function DosePreview({
  draft,
  replacingId,
}: {
  draft: CustomDoseDraft;
  replacingId?: string;
}) {
  const doses = useStore((s) => s.doses);
  const halfLife = useStore((s) => s.prefs.halfLife);
  const now = useNow();
  const palette = getAppPalette(useAppScheme());
  const bedtime = nextPlannedBedtime(now);
  const preview = previewDose(
    doses,
    { ...draft, id: 'preview', mg: Number(draft.mg) },
    bedtime,
    halfLife,
    replacingId,
  );
  if (!Number.isFinite(preview.dailyTotal) || Number(draft.mg) <= 0)
    return null;
  return (
    <SectionCard>
      <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>
        After saving
      </Text>
      <Text style={{ ...typeRamp.body, color: palette.textPrimary }}>
        {preview.dailyTotal} mg on{' '}
        {new Date(draft.timestamp).toLocaleDateString()}
      </Text>
      <Text style={{ ...typeRamp.subheadline, color: palette.textSecondary }}>
        Estimated {Math.round(preview.bedtimeMg)} mg remaining at{' '}
        {new Date(bedtime).toLocaleTimeString([], {
          hour: 'numeric',
          minute: '2-digit',
        })}{' '}
        bedtime.
      </Text>
      <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>
        Model estimate using a {halfLife}-hour half-life. Sample data excluded.
      </Text>
    </SectionCard>
  );
}
export function DoseUndoNotice() {
  const insets = useSafeAreaInsets();
  const undo = useStore((s) => s.doseUndo);
  const undoChange = useStore((s) => s.undoDoseChange);
  const onboarding = useStore((s) => s.onboarding);
  const now = useNow(1000);
  const palette = getAppPalette(useAppScheme());
  if (
    !undo ||
    now >= undo.expiresAt ||
    (onboarding.completed && !onboarding.appWalkthroughCompleted)
  )
    return null;
  return (
    <View
      testID="caffeine-undo-notice"
      style={{
        gap: spacing.xs,
        marginBottom: insets.bottom,
        padding: spacing.sm,
        backgroundColor: palette.card,
        borderRadius: 16,
        borderColor: palette.cardBorder,
        borderWidth: 1,
      }}
    >
      <Text
        accessibilityLiveRegion="polite"
        style={{ ...typeRamp.subheadline, color: palette.textSecondary }}
      >
        Caffeine {undo.before ? (undo.after ? 'updated' : 'deleted') : 'added'}.
        Undo is available.
      </Text>
      <Button
        title="Undo"
        accessibilityLabel="Undo caffeine change"
        variant="tinted"
        onPress={() => undoChange(Date.now())}
      />
    </View>
  );
}
export function ServingCalculator({
  onApply,
}: {
  onApply: (mg: number) => void;
}) {
  const palette = getAppPalette(useAppScheme());
  const [mode, setMode] = useState<'servings' | 'volume'>('servings');
  const [amount, setAmount] = useState('95');
  const [quantity, setQuantity] = useState('1');
  const [reference, setReference] = useState('100');
  const result = calculateServing(mode, amount, quantity, reference);
  return (
    <View style={{ gap: spacing.sm }}>
      <SectionHeader title="Serving calculator" />
      <SegmentedControl
        value={mode}
        onChange={setMode}
        options={[
          { key: 'servings', label: 'Servings' },
          { key: 'volume', label: 'Label volume' },
        ]}
      />
      <FieldInput
        accessibilityLabel="Label caffeine in mg"
        placeholder="Caffeine in mg per serving or label volume"
        value={amount}
        onChangeText={setAmount}
        keyboardType="decimal-pad"
      />
      {mode === 'volume' && (
        <FieldInput
          accessibilityLabel="Label reference volume in ml"
          placeholder="Label volume in ml"
          value={reference}
          onChangeText={setReference}
          keyboardType="decimal-pad"
        />
      )}
      <FieldInput
        accessibilityLabel={
          mode === 'volume' ? 'Consumed volume in ml' : 'Number of servings'
        }
        placeholder={mode === 'volume' ? 'Consumed ml' : 'Servings'}
        value={quantity}
        onChangeText={setQuantity}
        keyboardType="decimal-pad"
      />
      <Text style={{ ...typeRamp.subheadline, color: palette.textSecondary }}>
        {result === null
          ? 'Enter positive values totaling 1–1999 mg.'
          : mode === 'volume'
            ? `${amount} mg ÷ ${reference} ml × ${quantity} ml = ${result} mg`
            : `${amount} mg × ${quantity} servings = ${result} mg`}
      </Text>
      <Button
        title={result === null ? 'Use calculated amount' : `Use ${result} mg`}
        disabled={result === null}
        onPress={() => result !== null && onApply(result)}
      />
    </View>
  );
}
export function DrinkLibrary() {
  const caffeine = useStore((s) => s.caffeine);
  const saveDrink = useStore((s) => s.saveDrink);
  const setFavorites = useStore((s) => s.setFavoriteDrinks);
  const palette = getAppPalette(useAppScheme());
  const [editing, setEditing] = useState<PersonalDrink | null>(null);
  const [label, setLabel] = useState('');
  const [mg, setMg] = useState('');
  const valid =
    label.trim().length > 0 &&
    Number.isInteger(Number(mg)) &&
    Number(mg) >= 1 &&
    Number(mg) <= 1999;
  const move = (id: string, delta: number) => {
    const ids = [...caffeine.favoriteIds];
    const index = ids.indexOf(id);
    const next = index + delta;
    if (index < 0 || next < 0 || next >= ids.length) return;
    [ids[index], ids[next]] = [ids[next], ids[index]];
    setFavorites(ids);
  };
  const drinks = availableDrinks(caffeine);
  const ordered = [
    ...caffeine.favoriteIds.flatMap((id) => {
      const drink = drinks.find((d) => d.id === id);
      return drink ? [drink] : [];
    }),
    ...drinks.filter((d) => !caffeine.favoriteIds.includes(d.id)),
  ];
  return (
    <View style={{ gap: spacing.md }}>
      <SectionHeader title="Personal drink library" />
      <Text style={{ ...typeRamp.subheadline, color: palette.textSecondary }}>
        Favorites appear in this order on Summary and Log. The four original
        presets stay unchanged.
      </Text>
      <SectionCard>
        <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>
          {editing ? 'Edit drink' : 'Create drink'}
        </Text>
        <FieldInput
          accessibilityLabel="Drink name"
          placeholder="Drink name"
          value={label}
          onChangeText={setLabel}
        />
        <FieldInput
          accessibilityLabel="Drink caffeine in mg"
          placeholder="Caffeine in mg"
          keyboardType="number-pad"
          value={mg}
          onChangeText={setMg}
        />
        <Button
          title="Save drink"
          disabled={!valid}
          onPress={() => {
            saveDrink({
              id:
                editing?.id ??
                `personal:${Date.now()}:${Math.random().toString(36).slice(2)}`,
              label: label.trim(),
              mg: Number(mg),
              archived: false,
            });
            setEditing(null);
            setLabel('');
            setMg('');
          }}
        />
        {editing && (
          <Button
            title="Cancel edit"
            variant="plain"
            onPress={() => {
              setEditing(null);
              setLabel('');
              setMg('');
            }}
          />
        )}
      </SectionCard>
      {ordered.map((drink) => {
        const index = caffeine.favoriteIds.indexOf(drink.id);
        return (
          <SectionCard key={drink.id}>
            <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>
              {drink.label} · {drink.mg} mg
            </Text>
            <View
              style={{
                flexDirection: 'row',
                flexWrap: 'wrap',
                gap: spacing.xs,
              }}
            >
              <Button
                title={index >= 0 ? 'Remove favorite' : 'Favorite'}
                accessibilityLabel={`${index >= 0 ? 'Remove favorite' : 'Favorite'} ${drink.label}`}
                variant="tinted"
                onPress={() =>
                  setFavorites(
                    index >= 0
                      ? caffeine.favoriteIds.filter((id) => id !== drink.id)
                      : [...caffeine.favoriteIds, drink.id],
                  )
                }
              />
              {index >= 0 && (
                <>
                  <Button
                    title="Move up"
                    accessibilityLabel={`Move ${drink.label} up`}
                    variant="plain"
                    disabled={index === 0}
                    onPress={() => move(drink.id, -1)}
                  />
                  <Button
                    title="Move down"
                    accessibilityLabel={`Move ${drink.label} down`}
                    variant="plain"
                    disabled={index === caffeine.favoriteIds.length - 1}
                    onPress={() => move(drink.id, 1)}
                  />
                </>
              )}
              {drink.id.startsWith('personal:') && (
                <>
                  <Button
                    title="Edit"
                    accessibilityLabel={`Edit ${drink.label}`}
                    variant="plain"
                    onPress={() => {
                      setEditing({ ...drink, archived: false });
                      setLabel(drink.label);
                      setMg(String(drink.mg));
                    }}
                  />
                  <Button
                    title="Archive"
                    accessibilityLabel={`Archive ${drink.label}`}
                    variant="plain"
                    onPress={() => saveDrink({ ...drink, archived: true })}
                  />
                </>
              )}
            </View>
          </SectionCard>
        );
      })}
      {caffeine.drinks
        .filter((d) => d.archived)
        .map((drink) => (
          <SectionCard key={drink.id}>
            <Text style={{ ...typeRamp.body, color: palette.textSecondary }}>
              {drink.label} · Archived
            </Text>
            <Button
              title={`Restore ${drink.label}`}
              variant="plain"
              onPress={() => saveDrink({ ...drink, archived: false })}
            />
          </SectionCard>
        ))}
    </View>
  );
}

export function QuickDoseSheet({
  drink,
  onClose,
  onSaved,
  returnFocusRef,
}: {
  drink: { label: string; mg: number } | null;
  onClose: () => void;
  onSaved?: () => void;
  returnFocusRef?: React.RefObject<View | null>;
}) {
  const now = useNow();
  const addDose = useStore((s) => s.addDose);
  const onboarding = useStore((s) => s.onboarding);
  const reduceMotion = useReduceMotion();
  return (
    <HealthFormSheet
      returnFocusRef={returnFocusRef}
      visible={!!drink}
      title={drink ? `Log ${drink.label}` : 'Quick Add'}
      onCancel={onClose}
      reduceMotion={reduceMotion}
      saveLabel="Log drink"
      saveDisabled={onboarding.completed && !onboarding.appWalkthroughCompleted}
      onSave={() => {
        if (
          !drink ||
          (onboarding.completed && !onboarding.appWalkthroughCompleted)
        )
          return;
        addDose({
          id: `dose:${Date.now()}:${Math.random().toString(36).slice(2)}`,
          timestamp: Date.now(),
          mg: drink.mg,
          source: drink.label,
        });
        if (!reduceMotion)
          void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(
            () => undefined,
          );
        if (onSaved) onSaved();
        else
          AccessibilityInfo.announceForAccessibility('Caffeine intake saved.');
        onClose();
      }}
    >
      {drink && (
        <DosePreview
          draft={{
            mg: String(drink.mg),
            source: drink.label,
            timestamp: now,
            note: '',
          }}
        />
      )}
    </HealthFormSheet>
  );
}
