import React, { useEffect, useState } from 'react';
import Constants from 'expo-constants';
import { Alert, Linking, Share, Switch, Text, View } from 'react-native';

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
import {
  getDailyTotalRows,
  makeDailyTotalsCSV,
  makeDoseEntriesCSV,
  makeVigilanceSessionsCSV,
} from '~/services/storage/export';
import { useStore } from '~/state/store';
import { haptics } from '~/services/platform/haptics';
import { formatClockHour } from '~/utils/format';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { typeRamp } from '~/theme/tokens';

const privacyPolicyUrl = 'https://nmapaye.github.io/aurora/privacy.html';
const supportUrl = 'https://nmapaye.github.io/aurora/support.html';

function openExternalUrl(url: string) {
  Linking.openURL(url).catch(() => {});
}

export default function SettingsScreen() {
  const palette = getAppPalette(useAppScheme());
  const prefs = useStore((s) => s.prefs);
  const setPrefs = useStore((s) => s.setPrefs);
  const appearanceMode = useStore((s) => s.appearanceMode);
  const setAppearanceMode = useStore((s) => s.setAppearanceMode);
  const deleteAllData = useStore((s) => s.deleteAllData);
  const doses = useStore((s) => s.doses);
  const vigilanceSessions = useStore((s) => s.vigilanceSessions);
  const appVersion = Constants.expoConfig?.version ?? '0.1.0';
  const [exportError, setExportError] = useState<string>();

  // Settings owns every export. Each CSV holds only recorded rows (daily
  // totals mark empty days "no record"), and names Manual or Sample Data.
  const exportCsv = async (label: string, message: string) => {
    setExportError(undefined);
    try {
      await Share.share({ message });
    } catch (error) {
      const reason = error instanceof Error ? error.message : 'Sharing unavailable.';
      setExportError(`Unable to export ${label}. ${reason}`);
    }
  };

  const confirmDeleteAll = () => {
    Alert.alert(
      'Delete all Aurora data?',
      'This removes every caffeine entry, sleep session, and reaction test stored in Aurora. Your Apple Health data is not changed.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            haptics.warning();
            deleteAllData();
          },
        },
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
      subtitle="Adjust estimates and your personal reference points."
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

      <SectionHeader prominence="prominent" title="Estimates and References" />
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
        footer="Your own sleep goal. Summary and Sleep compare against it, and the alertness estimate uses it."
      />
      {/* Stored as prefs.dailyLimitMg for compatibility; presented only as a
          number the user picks, never as a limit, allowance, or guideline. */}
      <StepperField
        label="Personal caffeine reference"
        value={prefs.dailyLimitMg}
        onChange={(value) => setPrefs({ dailyLimitMg: Math.round(value) })}
        step={20}
        min={0}
        max={1000}
        formatValue={(value) => `${Math.round(value)} mg`}
        footer="A daily amount you choose for your own reference. It is not a recommended or safe amount."
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
        footer="The time you choose for the cutoff marker and optional reminder."
      />

      <SectionHeader prominence="prominent" title="Notifications" />
      <SectionCard>
        <ListRow
          title="Cutoff reminder"
          subtitle={`Daily at ${formatClockHour(prefs.cutoffHour)}, the cutoff time you chose.`}
          accessory={
            <Switch
              accessibilityLabel="Cutoff reminder"
              value={prefs.notifyCutoff}
              onValueChange={(value) => setPrefs({ notifyCutoff: value })}
              trackColor={{ true: palette.tint }}
            />
          }
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
        <ListRow
          title="Export Caffeine Entries"
          subtitle={`CSV of every recorded entry (${doses.length}), with its source.`}
          onPress={() => exportCsv('caffeine entries', makeDoseEntriesCSV(doses))}
        />
        <ListRow
          title="Export Daily Caffeine Totals"
          subtitle="CSV by day. Days without entries are marked “no record”, not 0 mg."
          onPress={() => exportCsv('daily totals', makeDailyTotalsCSV(getDailyTotalRows(doses, Date.now())))}
        />
        <ListRow
          title="Export Reaction Tests"
          subtitle={`CSV of every Reaction Test (${vigilanceSessions.length}), with its source.`}
          onPress={() =>
            exportCsv(
              'Reaction Tests',
              makeVigilanceSessionsCSV([...vigilanceSessions].sort((a, b) => a.completedAt - b.completedAt)),
            )
          }
        />
        {exportError ? (
          <Text
            accessibilityRole="alert"
            accessibilityLabel={exportError}
            style={{ ...typeRamp.footnote, color: palette.destructive }}
          >
            {exportError}
          </Text>
        ) : null}
        <Button title="Delete All Data" role="destructive" onPress={confirmDeleteAll} />
      </SectionCard>
    </AppScreen>
  );
}
