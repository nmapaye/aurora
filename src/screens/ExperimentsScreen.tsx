import React, { useState } from 'react';
import DateTimePicker from '@react-native-community/datetimepicker';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { SectionCard, SectionHeader } from '~/components/ui';
import {
  PlanningField as Field,
  PlanningText as Text,
  planningId,
  timeText,
} from '~/features/planning/components';
import {
  experimentWindow,
  validExperiment,
  type Experiment,
} from '~/features/planning/model';
import useNow from '~/hooks/useNow';
import { goBack } from '~/navigation';
import { useStore } from '~/state/store';
import { addCalendarDays, localDateKey } from '~/utils/calendar';
export default function ExperimentsScreen() {
  const {
      planning,
      setPlanning,
      onboarding,
      doses,
      caffeine,
      sleeps,
      vigilanceSessions,
    } = useStore(),
    now = useNow();
  const disabled = onboarding.completed && !onboarding.appWalkthroughCompleted;
  const [rating, setRating] = useState(3),
    [note, setNote] = useState(''),
    [checkTime, setCheckTime] = useState<number | null>(null),
    [checkPicker, setCheckPicker] = useState(false);
  const fresh = (): Experiment => ({
    id: planningId('experiment'),
    question: '',
    baseline: {
      start: localDateKey(addCalendarDays(now, -14)),
      end: localDateKey(addCalendarDays(now, -8)),
    },
    comparison: {
      start: localDateKey(addCalendarDays(now, -7)),
      end: localDateKey(now),
    },
  });
  const [draft, setDraft] = useState<Experiment>(fresh),
    [picker, setPicker] = useState<{
      period: 'baseline' | 'comparison';
      edge: 'start' | 'end';
    } | null>(null),
    [message, setMessage] = useState('');
  const labelValue = (v: number | null, unit: string) =>
    v === null ? 'No data' : `${v.toFixed(1)} ${unit}`;
  return (
    <AppScreen
      title="Personal Experiments"
      trailing={<Button title="Close" variant="plain" onPress={goBack} />}
    >
      <SectionHeader title="Alertness check-in" />
      <SectionCard>
        <Text>
          How alert do you feel? 1 means very sleepy; 5 means very alert. This
          subjective scale is independent of reaction-test scores.
        </Text>
        {[1, 2, 3, 4, 5].map((n) => (
          <Button
            key={n}
            title={`${n}${rating === n ? ' selected' : ''}`}
            accessibilityLabel={`Rating ${n} of 5`}
            accessibilityValue={{
              text: rating === n ? 'Selected' : 'Not selected',
            }}
            disabled={disabled}
            onPress={() => setRating(n)}
          />
        ))}
        <Button
          title={`Check-in time ${checkTime === null ? 'Now' : timeText(checkTime)}`}
          disabled={disabled}
          onPress={() => setCheckPicker(!checkPicker)}
        />
        {checkPicker ? (
          <DateTimePicker
            mode="datetime"
            value={new Date(checkTime ?? now)}
            maximumDate={new Date(now)}
            onChange={(_e, d) => {
              if (d) setCheckTime(d.getTime());
            }}
          />
        ) : null}
        <Field
          label="Check-in note"
          value={note}
          onChange={setNote}
          disabled={disabled}
        />
        <Button
          title="Save check-in"
          disabled={
            disabled ||
            note.length > 2000 ||
            (checkTime !== null && checkTime > now)
          }
          onPress={() => {
            setPlanning({
              checkIns: [
                ...planning.checkIns,
                {
                  id: planningId('checkin'),
                  timestamp: checkTime ?? Date.now(),
                  rating,
                  note: note.trim(),
                },
              ],
            });
            setNote('');
            setCheckTime(null);
            setCheckPicker(false);
            setMessage('Check-in saved.');
          }}
        />
        {planning.checkIns
          .slice()
          .sort((a, b) => b.timestamp - a.timestamp)
          .map((c) => (
            <SectionCard key={c.id}>
              <Text>
                {timeText(c.timestamp)}: {c.rating} / 5. {c.note}
              </Text>
              <Button
                title={`Delete check-in ${timeText(c.timestamp)}`}
                disabled={disabled}
                variant="plain"
                onPress={() =>
                  setPlanning({
                    checkIns: planning.checkIns.filter((x) => x.id !== c.id),
                  })
                }
              />
            </SectionCard>
          ))}
      </SectionCard>
      <SectionHeader title="Experiment journal" />
      <SectionCard>
        <Text>
          Define a question and two separate date ranges. Results describe your
          recorded observations. They cannot show that caffeine caused a change.
          Missing records are not treated as zero; Sample Data is excluded.
        </Text>
        <Field
          label="Experiment question"
          value={draft.question}
          onChange={(question) => setDraft({ ...draft, question })}
          disabled={disabled}
        />
        {(['baseline', 'comparison'] as const).map((period) =>
          (['start', 'end'] as const).map((edge) => (
            <Button
              key={`${period}-${edge}`}
              title={`${period} ${edge}: ${draft[period][edge]}`}
              disabled={disabled}
              onPress={() => setPicker({ period, edge })}
            />
          )),
        )}
        {picker ? (
          <DateTimePicker
            mode="date"
            value={new Date(`${draft[picker.period][picker.edge]}T12:00:00`)}
            onChange={(_e, d) => {
              if (d)
                setDraft({
                  ...draft,
                  [picker.period]: {
                    ...draft[picker.period],
                    [picker.edge]: localDateKey(d.getTime()),
                  },
                });
            }}
          />
        ) : null}
        <Text>
          Dates are inclusive in your device's local calendar. Baseline must
          finish before comparison starts; each range can span up to one year.
          Future dates show only records available through now.
        </Text>
        <Button
          title="Save experiment"
          disabled={disabled || !validExperiment(draft)}
          onPress={() => {
            setPlanning({
              experiments: [
                ...planning.experiments.filter((e) => e.id !== draft.id),
                { ...draft, question: draft.question.trim() },
              ],
            });
            setMessage('Experiment saved.');
            setPicker(null);
          }}
        />
        <Button
          title="New experiment"
          disabled={disabled}
          variant="plain"
          onPress={() => {
            setDraft(fresh());
            setPicker(null);
          }}
        />
        {message ? <Text>{message}</Text> : null}
      </SectionCard>
      {planning.experiments.map((e) => (
        <SectionCard key={e.id}>
          <Text>{e.question}</Text>
          {(['baseline', 'comparison'] as const).map((period) => {
            const w = experimentWindow(
              e[period],
              doses,
              caffeine.zeroDays,
              sleeps,
              planning.checkIns,
              vigilanceSessions,
              now,
            );
            return (
              <SectionCard key={period}>
                <Text>
                  {period}: {e[period].start} through {e[period].end}. {w.days}{' '}
                  days elapsed.
                </Text>
                <Text>
                  Daily caffeine mean: {labelValue(w.caffeine.mean, 'mg')};{' '}
                  {w.caffeine.count} recorded or confirmed zero days,{' '}
                  {w.caffeine.missingDays} missing days.
                </Text>
                <Text>
                  Daily sleep mean: {labelValue(w.sleep.mean, 'hours')};{' '}
                  {w.sleep.count} recorded wake dates, {w.sleep.missingDays}{' '}
                  missing days. Includes naps, with overlapping time counted
                  once.
                </Text>
                <Text>
                  Subjective alertness mean:{' '}
                  {labelValue(w.checkIns.mean, '/ 5')}; {w.checkIns.count}{' '}
                  check-ins.
                </Text>
                <Text>
                  Mean of per-test median reaction times:{' '}
                  {labelValue(w.vigilance.mean, 'ms')}; {w.vigilance.count}{' '}
                  eligible completed tests.
                </Text>
              </SectionCard>
            );
          })}
          <Text>
            Descriptive observations only. Different sample counts, unrecorded
            days, and changes in routine can affect these summaries. No paired
            or causal inference is calculated.
          </Text>
          <Button
            title={`Edit experiment ${e.question}`}
            disabled={disabled}
            onPress={() => {
              setDraft({
                ...e,
                baseline: { ...e.baseline },
                comparison: { ...e.comparison },
              });
              setPicker(null);
            }}
          />
          <Button
            title={`Delete experiment ${e.question}`}
            disabled={disabled}
            variant="plain"
            onPress={() => {
              setPlanning({
                experiments: planning.experiments.filter((x) => x.id !== e.id),
              });
              if (draft.id === e.id) setDraft(fresh());
            }}
          />
        </SectionCard>
      ))}
    </AppScreen>
  );
}
