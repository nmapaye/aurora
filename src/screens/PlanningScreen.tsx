import MetricExplanation from '~/features/insights/MetricExplanation';
import React, { useState } from 'react';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { SectionCard, SectionHeader } from '~/components/ui';
import {
  PlanningField as Field,
  PlanningText as Text,
  ProjectionCurve,
  planningId,
  timeText,
  validNumber,
} from '~/features/planning/components';
import {
  projectScenario,
  scenarioInputs,
  thresholdCrossing,
  validScenario,
  type Scenario,
} from '~/features/planning/model';
import { nextScheduledSleep } from '~/features/sleep/upgrades';
import useNow from '~/hooks/useNow';
import { goBack, navigate } from '~/navigation';
import { useStore } from '~/state/store';
export default function PlanningScreen() {
  const {
    planning,
    setPlanning,
    doses,
    sleeps,
    prefs,
    sleepRoutines,
    onboarding,
  } = useStore();
  const now = useNow(),
    disabled = onboarding.completed && !onboarding.appWalkthroughCompleted;
  const [draft, setDraft] = useState<Scenario>({
    id: planningId('scenario'),
    name: 'New scenario',
    doses: [],
  });
  const [label, setLabel] = useState('Coffee'),
    [mg, setMg] = useState('95'),
    [offset, setOffset] = useState('60'),
    [editingDose, setEditingDose] = useState<string | null>(null);
  const [compare, setCompare] = useState<string | null>(null),
    [threshold, setThreshold] = useState(String(planning.thresholdMg));
  const [hours, setHours] = useState(planning.sensitivityHours.map(String)),
    [focusStart, setFocusStart] = useState(String(planning.focus.startMinutes)),
    [focusEnd, setFocusEnd] = useState(String(planning.focus.endMinutes));
  const [cursor, setCursor] = useState(0),
    [table, setTable] = useState(false),
    [message, setMessage] = useState('');
  const bedtime = nextScheduledSleep(sleepRoutines, now).bedtime;
  const other = planning.scenarios.find((s) => s.id === compare) ?? {
    id: 'baseline',
    name: 'Recorded baseline only',
    doses: [],
  };
  const a = projectScenario(
      draft,
      doses,
      sleeps,
      prefs,
      now,
      bedtime,
      planning.focus,
    ),
    b = projectScenario(
      other,
      doses,
      sleeps,
      prefs,
      now,
      bedtime,
      planning.focus,
    );
  const crossing = thresholdCrossing(
    scenarioInputs(draft, doses, now),
    prefs.halfLife,
    planning.thresholdMg,
    now,
  );
  const effectiveCursor = Math.min(cursor, a.curve.length - 1);
  const point = a.curve[effectiveCursor];
  const eventLabel = (event: string | null) =>
    event === 'before-dose'
      ? ' immediately before dose'
      : event === 'dose'
        ? ' at dose time'
        : '';
  const doseValid =
    label.trim().length > 0 &&
    label.length <= 200 &&
    validNumber(mg, 0, 2000) &&
    validNumber(offset, 0, 10080);
  const reset = () => {
    setDraft({ id: planningId('scenario'), name: 'New scenario', doses: [] });
    setEditingDose(null);
    setMessage('');
  };
  return (
    <AppScreen
      title="Caffeine Planning"
      trailing={<Button title="Close" variant="plain" onPress={goBack} />}
    >
      <SectionCard>
        <Text>
          Hypothetical schedules never change your intake history. Saved dose
          times are minutes after the displayed projection start; comparisons
          use the same current time, recorded baseline, and next scheduled
          bedtime. Sample Data is excluded.
        </Text>
        <Text>
          Projection starts {timeText(now)}. Bedtime {timeText(bedtime)}.
        </Text>
      </SectionCard>
      <SectionHeader title="Scenario editor" />
      <SectionCard>
        <Field
          label="Scenario name"
          value={draft.name}
          onChange={(name) => setDraft({ ...draft, name })}
          disabled={disabled}
        />
        {draft.doses.map((d) => (
          <SectionCard key={d.id}>
            <Text>
              {d.label}: {d.mg} mg, {d.offsetMinutes} minutes from now (
              {timeText(now + d.offsetMinutes * 60000)})
            </Text>
            <Button
              title={`Edit planned ${d.label}`}
              disabled={disabled}
              onPress={() => {
                setEditingDose(d.id);
                setLabel(d.label);
                setMg(String(d.mg));
                setOffset(String(d.offsetMinutes));
              }}
            />
            <Button
              title={`Remove planned ${d.label}`}
              disabled={disabled}
              variant="plain"
              onPress={() => {
                setDraft({
                  ...draft,
                  doses: draft.doses.filter((x) => x.id !== d.id),
                });
                if (editingDose === d.id) setEditingDose(null);
              }}
            />
          </SectionCard>
        ))}
        <Field
          label="Planned drink name"
          value={label}
          onChange={setLabel}
          disabled={disabled}
        />
        <Field
          label="Planned caffeine mg"
          value={mg}
          onChange={setMg}
          disabled={disabled}
          numeric
        />
        <Field
          label="Minutes from now"
          value={offset}
          onChange={setOffset}
          disabled={disabled}
          numeric
        />
        <Text>
          Enter 0–10080 minutes (up to seven days). A zero-minute dose is
          hypothetical at the projection start. Amounts are your assumptions.
        </Text>
        <Button
          title={
            editingDose ? 'Update hypothetical dose' : 'Add hypothetical dose'
          }
          disabled={
            disabled ||
            !doseValid ||
            (!editingDose && draft.doses.length >= 100)
          }
          onPress={() => {
            const dose = {
              id: editingDose ?? planningId('dose'),
              label: label.trim(),
              mg: Number(mg),
              offsetMinutes: Number(offset),
            };
            setDraft({
              ...draft,
              doses: editingDose
                ? draft.doses.map((d) => (d.id === editingDose ? dose : d))
                : [...draft.doses, dose],
            });
            setEditingDose(null);
            setMessage('');
          }}
        />
        {editingDose ? (
          <Button
            title="Cancel dose edit"
            variant="plain"
            onPress={() => setEditingDose(null)}
          />
        ) : null}
        <Button
          title="Save scenario"
          disabled={disabled || !validScenario(draft)}
          onPress={() => {
            const saved = { ...draft, name: draft.name.trim() };
            setPlanning({
              scenarios: [
                ...planning.scenarios.filter((s) => s.id !== draft.id),
                saved,
              ],
            });
            setMessage('Scenario saved. Intake history unchanged.');
          }}
        />
        <Button
          title="New scenario"
          disabled={disabled}
          variant="plain"
          onPress={reset}
        />
        {message ? <Text>{message}</Text> : null}
      </SectionCard>
      <SectionHeader title="Saved scenarios" />
      <SectionCard>
        {planning.scenarios.length === 0 ? (
          <Text>No saved scenarios.</Text>
        ) : (
          planning.scenarios.map((s) => (
            <SectionCard key={s.id}>
              <Button
                title={`Open ${s.name}`}
                disabled={disabled}
                onPress={() => {
                  setDraft({ ...s, doses: s.doses.map((d) => ({ ...d })) });
                  setEditingDose(null);
                  setMessage('');
                }}
              />
              <Button
                title={`Compare with ${s.name}`}
                onPress={() => setCompare(s.id)}
              />
              <Button
                title={`Delete ${s.name}`}
                disabled={disabled}
                variant="plain"
                onPress={() => {
                  setPlanning({
                    scenarios: planning.scenarios.filter((x) => x.id !== s.id),
                  });
                  if (draft.id === s.id) reset();
                  if (compare === s.id) setCompare(null);
                }}
              />
            </SectionCard>
          ))
        )}
        <Button
          title="Compare with recorded baseline"
          variant="plain"
          onPress={() => setCompare(null)}
        />
      </SectionCard>
      <SectionHeader title="Same-baseline comparison" />
      <SectionCard>
        <Text>
          Recorded today through {timeText(now)}: {a.baselineTodayMg.toFixed(0)}{' '}
          mg.
        </Text>
        <Text>
          {draft.name}: {a.plannedMg.toFixed(0)} mg planned;{' '}
          {a.bedtimeMg.toFixed(1)} mg estimated at bedtime.
        </Text>
        <Text>
          {other.name}: {b.plannedMg.toFixed(0)} mg planned;{' '}
          {b.bedtimeMg.toFixed(1)} mg estimated at bedtime.
        </Text>
        <Text>
          Planned totals cover every dose in each schedule. Bedtime estimates
          include only doses at or before that bedtime.
        </Text>
      </SectionCard>
      <SectionHeader title="Projected caffeine curve" />
      <SectionCard>
        <ProjectionCurve points={a.curve} />
        <Text>
          Time increases left to right. The height represents modeled caffeine
          in mg. Points are hourly with exact dose times included; the model
          assumes immediate absorption.
        </Text>
        <Text>
          {timeText(point.timestamp)}
          {eventLabel(point.event)}: {point.mg.toFixed(1)} mg, alertness
          estimate {point.alertness.toFixed(0)} / 100.
        </Text>
        <Button
          title="Previous projection time"
          disabled={effectiveCursor === 0}
          onPress={() => setCursor(Math.max(0, effectiveCursor - 1))}
        />
        <Button
          title="Next projection time"
          disabled={effectiveCursor >= a.curve.length - 1}
          onPress={() =>
            setCursor(Math.min(a.curve.length - 1, effectiveCursor + 1))
          }
        />
        <Button
          title={table ? 'Hide projection table' : 'Show projection table'}
          variant="plain"
          onPress={() => setTable(!table)}
        />
        {table
          ? a.curve.map((p) => (
              <Text key={p.timestamp}>
                {timeText(p.timestamp)}
                {eventLabel(p.event)}: {p.mg.toFixed(1)} mg;{' '}
                {p.alertness.toFixed(0)} / 100 alertness.
              </Text>
            ))
          : null}
      </SectionCard>
      <SectionHeader title="Mathematical threshold" />
      <SectionCard>
        <Field
          label="Threshold mg"
          value={threshold}
          onChange={setThreshold}
          numeric
          disabled={disabled}
        />
        <Button
          title="Apply threshold"
          disabled={disabled || !validNumber(threshold, 0.1, 2000)}
          onPress={() => setPlanning({ thresholdMg: Number(threshold) })}
        />
        <Text>
          Estimated at or below {planning.thresholdMg} mg after the final
          hypothetical dose:{' '}
          {crossing === null ? 'Unavailable' : timeText(crossing)}. This is
          exponential decay math, not a safe-to-sleep threshold. Later unplanned
          intake changes the estimate.
        </Text>
      </SectionCard>
      <SectionHeader title="Half-life sensitivity" />
      <SectionCard>
        <Text>
          Compare three assumptions without changing your active{' '}
          {prefs.halfLife}-hour preference.
        </Text>
        {hours.map((h, i) => (
          <Field
            key={i}
            label={`Half-life ${i + 1} hours`}
            value={h}
            onChange={(v) => setHours(hours.map((x, j) => (i === j ? v : x)))}
            numeric
            disabled={disabled}
          />
        ))}
        <Button
          title="Apply sensitivity values"
          disabled={disabled || hours.some((h) => !validNumber(h, 0.5, 24))}
          onPress={() =>
            setPlanning({
              sensitivityHours: hours.map(Number) as [number, number, number],
            })
          }
        />
        {planning.sensitivityHours.map((h, i) => (
          <Text key={i}>
            {h}h half-life:{' '}
            {projectScenario(
              draft,
              doses,
              sleeps,
              { ...prefs, halfLife: h },
              now,
              bedtime,
              planning.focus,
            ).bedtimeMg.toFixed(1)}{' '}
            mg at bedtime.
          </Text>
        ))}
      </SectionCard>
      <SectionHeader title="Desired focus window" />
      <SectionCard>
        <Field
          label="Focus starts in minutes"
          value={focusStart}
          onChange={setFocusStart}
          numeric
          disabled={disabled}
        />
        <Field
          label="Focus ends in minutes"
          value={focusEnd}
          onChange={setFocusEnd}
          numeric
          disabled={disabled}
        />
        <Button
          title="Apply focus window"
          disabled={
            disabled ||
            !validNumber(focusStart, 0, 10080) ||
            !validNumber(focusEnd, 0, 10080) ||
            Number(focusEnd) <= Number(focusStart)
          }
          onPress={() =>
            setPlanning({
              focus: {
                startMinutes: Number(focusStart),
                endMinutes: Number(focusEnd),
              },
            })
          }
        />
        <Text>
          {timeText(now + planning.focus.startMinutes * 60000)} to{' '}
          {timeText(now + planning.focus.endMinutes * 60000)}. Mean alertness
          model estimate: {draft.name} {a.focusMean.toFixed(1)} / 100;{' '}
          {other.name} {b.focusMean.toFixed(1)} / 100. {a.focusSamples}{' '}
          projection points at 15-minute intervals plus the endpoint. These are
          model outputs, not observed results or an optimal-dose recommendation.
          Future sleep is unknown.
        </Text>
      </SectionCard>
      <MetricExplanation metric="scenarioCaffeine" />
      <MetricExplanation metric="alertness" />
      <Button
        title="Reduction and daily budget"
        onPress={() => navigate('PlanningTargets')}
      />
      <Button
        title="Check-ins and experiments"
        onPress={() => navigate('Experiments')}
      />
    </AppScreen>
  );
}
