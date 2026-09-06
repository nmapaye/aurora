import React, { useState } from 'react';
import DateTimePicker from '@react-native-community/datetimepicker';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { SectionCard, SectionHeader } from '~/components/ui';
import {
  PlanningField as Field,
  PlanningText as Text,
  planningId,
  validNumber,
} from '~/features/planning/components';
import {
  budgetBalance,
  reductionTargets,
  validReduction,
} from '~/features/planning/model';
import useNow from '~/hooks/useNow';
import { goBack } from '~/navigation';
import { useStore } from '~/state/store';
import { localDateKey } from '~/utils/calendar';
export default function PlanningTargetsScreen() {
  const { planning, setPlanning, onboarding } = useStore(),
    now = useNow();
  const disabled = onboarding.completed && !onboarding.appWalkthroughCompleted;
  const [startDate, setStartDate] = useState(
      planning.reduction?.startDate ?? localDateKey(now),
    ),
    [datePicker, setDatePicker] = useState(false);
  const [startMg, setStartMg] = useState(
      String(planning.reduction?.startMg ?? 200),
    ),
    [endMg, setEndMg] = useState(String(planning.reduction?.endMg ?? 100)),
    [days, setDays] = useState(String(planning.reduction?.days ?? 14));
  const [target, setTarget] = useState(String(planning.budget.targetMg)),
    [name, setName] = useState('Coffee'),
    [amount, setAmount] = useState('95');
  const plan = {
      startDate,
      startMg: Number(startMg),
      endMg: Number(endMg),
      days: Number(days),
    },
    balance = budgetBalance(planning.budget);
  return (
    <AppScreen
      title="Caffeine Targets"
      trailing={<Button title="Close" variant="plain" onPress={goBack} />}
    >
      <SectionCard>
        <Text>
          Choose your own targets. These plans never add doses or change your
          daily limit preference. Targets are planning numbers, not medical
          advice.
        </Text>
      </SectionCard>
      <SectionHeader title="Gradual reduction" />
      <SectionCard>
        <Button
          title={`Start date ${startDate}`}
          disabled={disabled}
          onPress={() => setDatePicker(!datePicker)}
        />
        {datePicker ? (
          <DateTimePicker
            mode="date"
            value={new Date(`${startDate}T12:00:00`)}
            onChange={(_e, d) => {
              if (d) setStartDate(localDateKey(d.getTime()));
            }}
          />
        ) : null}
        <Field
          label="Starting daily caffeine mg"
          value={startMg}
          onChange={setStartMg}
          disabled={disabled}
          numeric
        />
        <Field
          label="Ending daily caffeine mg"
          value={endMg}
          onChange={setEndMg}
          disabled={disabled}
          numeric
        />
        <Field
          label="Reduction days"
          value={days}
          onChange={setDays}
          disabled={disabled}
          numeric
        />
        <Text>
          Use 2–365 whole days, with an ending amount no greater than the
          starting amount. The first and last dates use your exact targets;
          intermediate days decrease evenly.
        </Text>
        <Button
          title="Save reduction plan"
          disabled={
            disabled ||
            !startMg.trim() ||
            !endMg.trim() ||
            !validReduction(plan)
          }
          onPress={() => setPlanning({ reduction: plan })}
        />
        {planning.reduction ? (
          <>
            <Button
              title="Delete reduction plan"
              disabled={disabled}
              variant="plain"
              onPress={() => setPlanning({ reduction: null })}
            />
            {reductionTargets(planning.reduction).map((day) => (
              <Text key={day.date}>
                {day.date}: {day.mg} mg target
              </Text>
            ))}
          </>
        ) : (
          <Text>No reduction plan saved.</Text>
        )}
      </SectionCard>
      <SectionHeader title="Daily budget" />
      <SectionCard>
        <Field
          label="Daily budget mg"
          value={target}
          onChange={setTarget}
          disabled={disabled}
          numeric
        />
        <Button
          title="Save daily budget"
          disabled={disabled || !validNumber(target, 0, 2000)}
          onPress={() =>
            setPlanning({
              budget: { ...planning.budget, targetMg: Number(target) },
            })
          }
        />
        <Text>
          {balance.allocatedMg} mg allocated against {planning.budget.targetMg}{' '}
          mg target.{' '}
          {balance.remainingMg >= 0
            ? `${balance.remainingMg} mg unused`
            : `${-balance.remainingMg} mg over target`}
          .
        </Text>
        {planning.budget.allocations.map((a) => (
          <SectionCard key={a.id}>
            <Text>
              {a.label}: {a.mg} mg
            </Text>
            <Button
              title={`Remove allocation ${a.label}`}
              disabled={disabled}
              variant="plain"
              onPress={() =>
                setPlanning({
                  budget: {
                    ...planning.budget,
                    allocations: planning.budget.allocations.filter(
                      (x) => x.id !== a.id,
                    ),
                  },
                })
              }
            />
          </SectionCard>
        ))}
        <Field
          label="Budget drink name"
          value={name}
          onChange={setName}
          disabled={disabled}
        />
        <Field
          label="Allocated caffeine mg"
          value={amount}
          onChange={setAmount}
          disabled={disabled}
          numeric
        />
        <Button
          title="Allocate planned drink"
          disabled={
            disabled ||
            !name.trim() ||
            name.length > 200 ||
            !validNumber(amount, 0, 2000) ||
            planning.budget.allocations.length >= 100
          }
          onPress={() =>
            setPlanning({
              budget: {
                ...planning.budget,
                allocations: [
                  ...planning.budget.allocations,
                  {
                    id: planningId('allocation'),
                    label: name.trim(),
                    mg: Number(amount),
                  },
                ],
              },
            })
          }
        />
        <Text>
          Allocations describe one planned day. They do not imply any drink was
          consumed.
        </Text>
      </SectionCard>
    </AppScreen>
  );
}
