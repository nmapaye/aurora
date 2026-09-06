import { validateManualSleep } from '~/features/sleep/manualSleep';
import React, { createRef, useRef, useState } from 'react';
import { Text, TextInput, View } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { HealthFormSheet } from '~/components/health';
import { SectionCard, SectionHeader } from '~/components/ui';
import {
  nextScheduledSleep,
  sleepTrends,
  validSleepTimes,
  type SleepTimes,
} from '~/features/sleep/upgrades';
import { formatSleepDuration } from '~/features/sleep/presentation';
import useAppScheme from '~/hooks/useAppScheme';
import useNow from '~/hooks/useNow';
import useReduceMotion from '~/hooks/useReduceMotion';
import { goBack, navigate } from '~/navigation';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { typeRamp } from '~/theme/tokens';
import { localDateKey } from '~/utils/calendar';
const weekdays = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const timeLabel = (minute: number) =>
  `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
const stamp = (time: number) =>
  new Date(time).toLocaleString([], {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
export default function SleepRoutinesScreen() {
  const {
    sleepRoutines: routines,
    setSleepRoutines,
    confirmNap,
    prefs,
    sleeps,
    onboarding,
  } = useStore();
  const now = useNow(1000),
    palette = getAppPalette(useAppScheme()),
    reduceMotion = useReduceMotion();
  const disabled = onboarding.completed && !onboarding.appWalkthroughCompleted;
  const [edit, setEdit] = useState<number | 'exception' | null>(null),
    [date, setDate] = useState(now);
  const [draft, setDraft] = useState<SleepTimes>(
    routines.weekly[new Date(now).getDay()],
  );
  const [napError, setNapError] = useState('');
  const [napPicker, setNapPicker] = useState<'start' | 'end' | null>(null);
  const napValidation = routines.timer?.end
    ? validateManualSleep({
        start: routines.timer.start,
        end: routines.timer.end,
      })
    : null;
  const [picker, setPicker] = useState<'bedtime' | 'wake' | 'date' | null>(
    null,
  );
  const [lead, setLead] = useState(String(routines.windDown.leadMinutes));
  const triggerRefs = useRef(new Map<string, React.RefObject<View | null>>());
  const [triggerKey, setTriggerKey] = useState<string>('exception');
  const triggerRef = (key: string) => {
    const existing = triggerRefs.current.get(key);
    if (existing) return existing;
    const ref = createRef<View>();
    triggerRefs.current.set(key, ref);
    return ref;
  };
  const planned = nextScheduledSleep(routines, now),
    trends = sleepTrends(sleeps, routines, prefs.targetSleep, now, 7);
  const open = (day: number | 'exception') => {
    setTriggerKey(String(day));
    setDraft(
      typeof day === 'number'
        ? routines.weekly[day]
        : routines.weekly[new Date(date).getDay()],
    );
    setEdit(day);
    setPicker(null);
  };
  const save = () => {
    if (disabled || !validSleepTimes(draft)) return;
    if (typeof edit === 'number')
      setSleepRoutines({
        weekly: routines.weekly.map((t, i) => (i === edit ? draft : t)),
      });
    else
      setSleepRoutines({
        exceptions: { ...routines.exceptions, [localDateKey(date)]: draft },
      });
    setEdit(null);
    setPicker(null);
  };
  const textStyle = { ...typeRamp.body, color: palette.textPrimary };
  const n = trends.filter((t) => t.bedtimeVariationMin !== null).length;
  return (
    <AppScreen
      title="Sleep Routines"
      trailing={<Button title="Close" variant="plain" onPress={goBack} />}
    >
      <SectionCard>
        <Text style={textStyle}>
          Next planned sleep: {stamp(planned.bedtime)} to {stamp(planned.wake)}
          {planned.daylightSavingAdjusted
            ? ' (adjusted for daylight saving)'
            : ''}
        </Text>
        <Text style={textStyle}>
          Times follow your device's local calendar. Times skipped by daylight
          saving move forward; if needed, wake time shifts to preserve the
          planned duration. Each weekday refers to the date bedtime starts.
        </Text>
      </SectionCard>
      <SectionHeader title="Weekly schedule" />
      <SectionCard>
        {weekdays.map((day, i) => (
          <Button
            key={day}
            ref={triggerRef(String(i))}
            title={`${day} ${timeLabel(routines.weekly[i].bedtime)} – ${timeLabel(routines.weekly[i].wake)}`}
            accessibilityLabel={`Edit ${day} sleep schedule`}
            accessibilityValue={{
              text: `Bedtime ${timeLabel(routines.weekly[i].bedtime)}, wake ${timeLabel(routines.weekly[i].wake)} ${routines.weekly[i].wake <= routines.weekly[i].bedtime ? 'next day' : 'same day'}`,
            }}
            variant="plain"
            disabled={disabled}
            onPress={() => open(i)}
          />
        ))}
      </SectionCard>
      <SectionHeader title="Schedule exceptions" />
      <Button
        ref={triggerRef('exception')}
        title="Add schedule exception"
        disabled={disabled}
        onPress={() => open('exception')}
      />
      {Object.entries(routines.exceptions)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([day, times]) => (
          <SectionCard key={day}>
            <Text style={textStyle}>
              {day}: {timeLabel(times.bedtime)} – {timeLabel(times.wake)}
            </Text>
            <Button
              title={`Remove exception ${day}`}
              disabled={disabled}
              variant="plain"
              onPress={() => {
                const exceptions = { ...routines.exceptions };
                delete exceptions[day];
                setSleepRoutines({ exceptions });
              }}
            />
          </SectionCard>
        ))}
      <SectionHeader title="Nap timer" />
      <SectionCard>
        {routines.timer ? (
          <>
            <Text style={textStyle}>
              Started {stamp(routines.timer.start)}.{' '}
              {formatSleepDuration(
                Math.max(0, (routines.timer.end ?? now) - routines.timer.start),
              )}
            </Text>
            {routines.timer.end ? (
              <>
                <Text style={textStyle}>
                  Confirm only the time you were asleep. This timer has not
                  saved a sleep entry.
                </Text>
                <Button
                  title={`Nap start ${stamp(routines.timer.start)}`}
                  disabled={disabled}
                  onPress={() => setNapPicker('start')}
                />
                <Button
                  title={`Nap end ${stamp(routines.timer.end)}`}
                  disabled={disabled}
                  onPress={() => setNapPicker('end')}
                />
                {napPicker ? (
                  <DateTimePicker
                    mode="datetime"
                    display="spinner"
                    value={new Date(routines.timer[napPicker]!)}
                    onChange={(_event, value) => {
                      if (!value) return;
                      const timer = {
                        ...routines.timer!,
                        [napPicker]: value.getTime(),
                      };
                      const validation = validateManualSleep({
                        start: timer.start,
                        end: timer.end!,
                      });
                      if (!validation.valid) {
                        setNapError(validation.message);
                        return;
                      }
                      setNapError('');
                      setSleepRoutines({ timer });
                    }}
                  />
                ) : null}
                {napError ? (
                  <Text accessibilityRole="alert" style={textStyle}>
                    {napError}
                  </Text>
                ) : null}
                {napValidation && !napValidation.valid ? (
                  <Text accessibilityRole="alert" style={textStyle}>
                    {napValidation.message}
                  </Text>
                ) : null}
                <Button
                  title="Confirm nap entry"
                  disabled={disabled || !napValidation?.valid}
                  onPress={() => {
                    confirmNap();
                    setNapPicker(null);
                  }}
                />
              </>
            ) : (
              <Button
                title="Finish nap timer"
                disabled={disabled || now <= routines.timer.start}
                onPress={() =>
                  setSleepRoutines({
                    timer: { ...routines.timer!, end: Date.now() },
                  })
                }
              />
            )}
            <Button
              title="Cancel nap timer"
              disabled={disabled}
              variant="plain"
              onPress={() => setSleepRoutines({ timer: null })}
            />
          </>
        ) : (
          <Button
            title="Start nap timer"
            disabled={disabled}
            onPress={() => setSleepRoutines({ timer: { start: Date.now() } })}
          />
        )}
      </SectionCard>
      <SectionHeader title="Sleep consistency and deficit" />
      <SectionCard>
        <Text style={textStyle}>
          {n} recorded main sleep {n === 1 ? 'episode' : 'episodes'} in 7 days.
          Variation is measured against the nearest scheduled bedtime. Sample
          Data is excluded.
        </Text>
        {trends.map((t) => (
          <Text key={t.date} style={textStyle}>
            {new Date(t.date).toLocaleDateString()}:{' '}
            {t.durationMs === null
              ? 'Missing sleep data'
              : `${formatSleepDuration(t.durationMs)} recorded, ${formatSleepDuration(t.deficitMs ?? 0)} below ${prefs.targetSleep}h target`}
            {t.bedtimeVariationMin === null
              ? ''
              : `; bed ${t.bedtimeVariationMin >= 0 ? '+' : ''}${t.bedtimeVariationMin} min, wake ${t.wakeVariationMin! >= 0 ? '+' : ''}${t.wakeVariationMin} min`}
          </Text>
        ))}
        <Text style={textStyle}>
          Positive variation means later than planned. Overlapping records count
          once. Missing days have no calculated deficit.
        </Text>
      </SectionCard>
      <SectionHeader title="Wind-down reminder" />
      <SectionCard>
        <Text style={textStyle}>
          Remind me before my scheduled bedtime. Notification permission is
          required. Aurora schedules the next 14 days when opened. If permission
          is denied or scheduling fails, the reminder turns off.
        </Text>
        <TextInput
          accessibilityLabel="Wind-down lead minutes"
          keyboardType="number-pad"
          editable={!disabled}
          value={lead}
          onChangeText={setLead}
          style={{ ...textStyle, minHeight: 44 }}
        />
        <Button
          title="Save reminder lead time"
          disabled={disabled || !/^\d+$/.test(lead) || Number(lead) > 180}
          onPress={() =>
            setSleepRoutines({
              windDown: { ...routines.windDown, leadMinutes: Number(lead) },
            })
          }
        />
        <Button
          title={
            routines.windDown.enabled
              ? 'Turn off wind-down reminder'
              : 'Turn on wind-down reminder'
          }
          disabled={disabled}
          onPress={() =>
            setSleepRoutines({
              windDown: {
                ...routines.windDown,
                enabled: !routines.windDown.enabled,
              },
            })
          }
        />
      </SectionCard>
      <Button
        title="Sleep journal and overlap review"
        variant="plain"
        onPress={() => navigate('SleepHistory')}
      />
      <HealthFormSheet
        title={typeof edit === 'number' ? weekdays[edit] : 'Schedule exception'}
        visible={edit !== null}
        reduceMotion={reduceMotion}
        returnFocusRef={triggerRefs.current.get(triggerKey)}
        onCancel={() => {
          setEdit(null);
          setPicker(null);
        }}
        onSave={save}
        saveDisabled={disabled || !validSleepTimes(draft)}
      >
        {edit === 'exception' ? (
          <Button
            title={`Date ${localDateKey(date)}`}
            onPress={() => setPicker('date')}
          />
        ) : null}
        <Button
          title={`Bedtime ${timeLabel(draft.bedtime)}`}
          onPress={() => setPicker('bedtime')}
        />
        <Button
          title={`Wake time ${timeLabel(draft.wake)}`}
          onPress={() => setPicker('wake')}
        />
        <Text style={textStyle}>
          {draft.wake <= draft.bedtime
            ? 'Wake time is on the following day.'
            : 'Wake time is on the same day.'}
        </Text>
        {picker ? (
          <DateTimePicker
            testID="routine-time-picker"
            mode={picker === 'date' ? 'date' : 'time'}
            display="spinner"
            value={
              picker === 'date'
                ? new Date(date)
                : new Date(
                    new Date(now).setHours(
                      Math.floor(draft[picker] / 60),
                      draft[picker] % 60,
                      0,
                      0,
                    ),
                  )
            }
            onChange={(_event, value) => {
              if (!value) return;
              if (picker === 'date') setDate(value.getTime());
              else
                setDraft({
                  ...draft,
                  [picker]: value.getHours() * 60 + value.getMinutes(),
                });
            }}
          />
        ) : null}
      </HealthFormSheet>
    </AppScreen>
  );
}
