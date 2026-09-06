import React from 'react';
import { View } from 'react-native';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { SectionCard } from '~/components/ui';
import { PlanningText as Text } from '~/features/planning/components';
import { defaultOwnership, type SummaryCard } from '~/features/ownership/model';
import { useStore } from '~/state/store';
import { goBack } from '~/navigation';
export const cardLabels: Record<SummaryCard, string> = {
  caffeine: 'Caffeine',
  'active-caffeine': 'Active Caffeine',
  sleep: 'Sleep',
  vigilance: 'Vigilance',
  cutoff: 'Caffeine Cutoff',
};
export default function SummarySettingsScreen() {
  const ownership = useStore((s) => s.ownership),
    setOwnership = useStore((s) => s.setOwnership),
    onboarding = useStore((s) => s.onboarding);
  const disabled = onboarding.completed && !onboarding.appWalkthroughCompleted;
  const move = (index: number, delta: number) => {
    const order = [...ownership.summary.order];
    [order[index], order[index + delta]] = [order[index + delta], order[index]];
    setOwnership({ ...ownership, summary: { ...ownership.summary, order } });
  };
  return (
    <AppScreen
      title="Customize Summary"
      trailing={<Button title="Done" onPress={goBack} />}
    >
      <Text>
        Hide or move metric cards. The walkthrough always shows the default
        cards and restores your choices afterward.
      </Text>
      {ownership.summary.order.map((key, index) => (
        <SectionCard key={key}>
          <Text>
            {index + 1}. {cardLabels[key]} ·{' '}
            {ownership.summary.hidden.includes(key) ? 'Hidden' : 'Shown'}
          </Text>
          <View style={{ gap: 8, flexDirection: 'row', flexWrap: 'wrap' }}>
            <Button
              title={`${ownership.summary.hidden.includes(key) ? 'Show' : 'Hide'} ${cardLabels[key]}`}
              disabled={disabled}
              onPress={() =>
                setOwnership({
                  ...ownership,
                  summary: {
                    ...ownership.summary,
                    hidden: ownership.summary.hidden.includes(key)
                      ? ownership.summary.hidden.filter((x) => x !== key)
                      : [...ownership.summary.hidden, key],
                  },
                })
              }
            />
            <Button
              title={`Move ${cardLabels[key]} up`}
              disabled={disabled || index === 0}
              onPress={() => move(index, -1)}
            />
            <Button
              title={`Move ${cardLabels[key]} down`}
              disabled={
                disabled || index === ownership.summary.order.length - 1
              }
              onPress={() => move(index, 1)}
            />
          </View>
        </SectionCard>
      ))}
      <Button
        title="Restore default cards"
        disabled={disabled}
        onPress={() =>
          setOwnership({ ...ownership, summary: defaultOwnership().summary })
        }
      />
    </AppScreen>
  );
}
