import React from 'react';
import { Linking } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import {
  SectionHeader,
  ListRow,
  SectionCard,
  SegmentedControl,
  StepperField,
} from '~/components/ui';
import { goBack } from '~/navigation';
import { useStore } from '~/state/store';

const privacyPolicyUrl = 'https://nmapaye.github.io/aurora/privacy.html';
const supportUrl = 'https://nmapaye.github.io/aurora/support.html';

function openExternalUrl(url: string) {
  Linking.openURL(url).catch(() => {});
}

export default function SettingsScreen() {
  const prefs = useStore((s) => s.prefs);
  const setPrefs = useStore((s) => s.setPrefs);
  const appearanceMode = useStore((s) => s.appearanceMode);
  const setAppearanceMode = useStore((s) => s.setAppearanceMode);

  return (
    <AppScreen
      title="Settings"
      subtitle="Tune caffeine and sleep guidance."
      trailing={<Button title="Done" variant="plain" onPress={goBack} />}
    >
      <SectionHeader prominence="prominent" title="Appearance" />
      <SectionCard>
        <SegmentedControl
          value={appearanceMode}
          onChange={setAppearanceMode}
          options={[
            { key: 'system', label: 'System' },
            { key: 'light', label: 'Light' },
            { key: 'dark', label: 'Dark' },
          ]}
        />
      </SectionCard>

      <SectionHeader prominence="prominent" title="Guidance" />
      <StepperField
        label="Caffeine half-life"
        value={prefs.halfLife}
        onChange={(value) => setPrefs({ halfLife: value })}
        step={0.5}
        min={0.5}
        max={16}
        formatValue={(value) => `${value.toFixed(1)} h`}
        footer="Used to estimate active caffeine."
      />
      <StepperField
        label="Daily sleep target"
        value={prefs.targetSleep}
        onChange={(value) => setPrefs({ targetSleep: value })}
        step={0.5}
        min={5}
        max={10}
        formatValue={(value) => `${value.toFixed(1)} h`}
        footer="Used for sleep guidance."
      />
      <StepperField
        label="Daily caffeine limit"
        value={prefs.dailyLimitMg}
        onChange={(value) => setPrefs({ dailyLimitMg: Math.round(value) })}
        step={20}
        min={0}
        max={1000}
        formatValue={(value) => `${Math.round(value)} mg`}
        footer="Shown in Insights."
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
        footer="Your daily guardrail."
      />

      <SectionHeader prominence="prominent" title="Notifications" />
      <SectionCard>
        <ListRow
          title="Cutoff reminder"
          subtitle={`Daily at ${prefs.cutoffHour}:00, so caffeine stays clear of bedtime.`}
        />
        <SegmentedControl
          value={prefs.notifyCutoff ? 'on' : 'off'}
          onChange={(value) => setPrefs({ notifyCutoff: value === 'on' })}
          options={[
            { key: 'off', label: 'Off' },
            { key: 'on', label: 'On' },
          ]}
        />
      </SectionCard>

      <SectionHeader prominence="prominent" title="About" />
      <SectionCard>
        <ListRow
          title="Current release focus"
          subtitle="Health sleep import, caffeine logging, vigilance testing, and insights."
        />
        <ListRow
          title="Privacy Policy"
          subtitle="Read-only Health sleep access, local storage, exports, and deletion."
          onPress={() => openExternalUrl(privacyPolicyUrl)}
        />
        <ListRow
          title="Support"
          subtitle="Get help, report issues, and avoid sharing private Health data."
          onPress={() => openExternalUrl(supportUrl)}
        />
        <ListRow
          title="Medical disclaimer"
          subtitle="Aurora is informational only and does not diagnose, treat, cure, or prevent any disease or condition."
        />
        <ListRow
          title="Availability"
          subtitle="Designed for iPhone and iPad."
        />
      </SectionCard>
    </AppScreen>
  );
}
