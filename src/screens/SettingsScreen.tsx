import React, { useEffect, useState } from 'react';
import Constants from 'expo-constants';
import { Alert, Linking, View } from 'react-native';

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
import { syncCutoffReminder } from '~/services/platform/notifications';
import { useStore } from '~/state/store';
import { formatClockHour } from '~/utils/format';

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
  const deleteAllData = useStore((s) => s.deleteAllData);
  const appVersion = Constants.expoConfig?.version ?? '0.1.0';

  const confirmDeleteAll = () => {
    Alert.alert(
      'Delete all Aurora data?',
      'This removes every caffeine entry, sleep session, and reaction test stored in Aurora. Your Apple Health data is not changed.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: deleteAllData },
      ],
    );
  };

  const [reminderStatus, setReminderStatus] = useState('Updating reminder…');
  const [reminderFailed, setReminderFailed] = useState(false);
  const [retry, setRetry] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setReminderStatus('Updating reminder…');
    setReminderFailed(false);
    syncCutoffReminder(prefs.notifyCutoff, prefs.cutoffHour)
      .then((scheduled) => {
        if (cancelled) return;
        const denied = prefs.notifyCutoff && !scheduled;
        setReminderFailed(denied);
        setReminderStatus(denied
          ? 'Notification permission is off. Allow notifications in system Settings, then retry.'
          : scheduled ? 'Reminder scheduled.' : 'Reminder off.');
      })
      .catch(() => {
        if (cancelled) return;
        setReminderFailed(true);
        setReminderStatus('Reminder status unknown. Retry to apply your choice.');
      });
    return () => { cancelled = true; };
  }, [prefs.notifyCutoff, prefs.cutoffHour, retry]);

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
        formatValue={(value) => formatClockHour(value)}
        footer="Your daily guardrail."
      />

      <SectionHeader prominence="prominent" title="Notifications" />
      <SectionCard>
        <ListRow
          title="Cutoff reminder"
          subtitle={`Daily at ${formatClockHour(prefs.cutoffHour)}, so caffeine stays clear of bedtime.`}
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

      <SectionCard>
        <View accessible accessibilityRole={reminderFailed ? 'alert' : undefined}
          accessibilityLiveRegion={reminderFailed ? 'assertive' : 'polite'}
          accessibilityLabel={reminderStatus}>
          <ListRow title="Reminder status" subtitle={reminderStatus} />
        </View>
        {reminderFailed && <Button title="Retry reminder" onPress={() => setRetry((value) => value + 1)} />}
      </SectionCard>

      <SectionHeader prominence="prominent" title="About" />
      <SectionCard>
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
        <ListRow title="Version" subtitle={appVersion} />
      </SectionCard>

      <SectionHeader prominence="prominent" title="Data" />
      <SectionCard>
        <ListRow
          title="Stored on this device"
          subtitle="Aurora keeps your entries on this iPhone or iPad. Deleting them does not change Apple Health."
        />
        <Button title="Delete All Data" role="destructive" onPress={confirmDeleteAll} />
      </SectionCard>
    </AppScreen>
  );
}
