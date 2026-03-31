import React from 'react';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import {
  ListRow,
  SectionCard,
  SectionTitle,
  StepperField,
} from '~/components/ui';
import { goBack } from '~/navigation';
import { useStore } from '~/state/store';

export default function SettingsScreen() {
  const prefs = useStore((s) => s.prefs);
  const setPrefs = useStore((s) => s.setPrefs);

  return (
    <AppScreen
      title="Settings"
      subtitle="Adjust the core assumptions Aurora uses for sleep protection and caffeine guidance."
      trailing={<Button title="Done" variant="plain" onPress={goBack} />}
    >
      <SectionTitle>Guidance</SectionTitle>
      <StepperField
        label="Caffeine half-life"
        value={prefs.halfLife}
        onChange={(value) => setPrefs({ halfLife: value })}
        step={0.5}
        min={0.5}
        max={16}
        formatValue={(value) => `${value.toFixed(1)} h`}
        footer="Used to estimate active caffeine and bedtime guidance."
      />
      <StepperField
        label="Daily sleep target"
        value={prefs.targetSleep}
        onChange={(value) => setPrefs({ targetSleep: value })}
        step={0.5}
        min={5}
        max={10}
        formatValue={(value) => `${value.toFixed(1)} h`}
        footer="Aurora tries to protect this amount of sleep when calculating your cutoff."
      />
      <StepperField
        label="Daily caffeine limit"
        value={prefs.dailyLimitMg}
        onChange={(value) => setPrefs({ dailyLimitMg: Math.round(value) })}
        step={20}
        min={0}
        max={1000}
        formatValue={(value) => `${Math.round(value)} mg`}
        footer="Shown in insights and adherence summaries."
      />
      <StepperField
        label="Cutoff hour"
        value={prefs.cutoffHour}
        onChange={(value) =>
          setPrefs({ cutoffHour: Math.max(0, Math.min(23, Math.round(value))) })
        }
        step={1}
        min={0}
        max={23}
        formatValue={(value) => `${Math.round(value)}:00`}
        footer="Used as the simple daily guardrail for late caffeine."
      />

      <SectionTitle>About</SectionTitle>
      <SectionCard>
        <ListRow
          title="Current release focus"
          subtitle="HealthKit-backed sleep import, manual intake logging, vigilance reaction testing, and on-device insights."
        />
        <ListRow
          title="Deferred for later"
          subtitle="Android health integration, sync, encrypted import/export, notifications, and background automation."
        />
      </SectionCard>
    </AppScreen>
  );
}
