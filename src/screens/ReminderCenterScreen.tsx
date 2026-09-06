import React, { useEffect, useState } from 'react';
import { AppState, Linking, View } from 'react-native';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { SectionCard, StepperField } from '~/components/ui';
import { PlanningText as Text } from '~/features/planning/components';
import { REMINDER_KINDS, type ReminderKind } from '~/features/ownership/model';
import {
  notificationPermission,
  syncReminderCenter,
  type ReminderPermission,
} from '~/services/platform/reminderCenter';
import { useStore } from '~/state/store';
import { goBack } from '~/navigation';
const labels: Record<ReminderKind, string> = {
  cutoff: 'Cutoff',
  windDown: 'Wind-down',
  checkIn: 'Check-in',
  weeklyReview: 'Weekly review',
};
const days = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const clock = (m: number) =>
  `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
export default function ReminderCenterScreen() {
  const ownership = useStore((s) => s.ownership),
    setOwnership = useStore((s) => s.setOwnership),
    routines = useStore((s) => s.sleepRoutines),
    setSleepRoutines = useStore((s) => s.setSleepRoutines),
    prefs = useStore((s) => s.prefs),
    setPrefs = useStore((s) => s.setPrefs),
    onboarding = useStore((s) => s.onboarding);
  const [permission, setPermission] =
      useState<ReminderPermission>('unavailable'),
    [error, setError] = useState(''),
    [busy, setBusy] = useState(false);
  const allowed = onboarding.completed && onboarding.appWalkthroughCompleted,
    disabled = !allowed;
  useEffect(() => {
    let current = true;
    const read = () =>
      notificationPermission().then((p) => {
        if (current) setPermission(p);
      });
    void read();
    const sub = AppState.addEventListener('change', (s) => {
      if (s === 'active') void read();
    });
    return () => {
      current = false;
      sub.remove();
    };
  }, []);
  const update = (
    kind: 'checkIn' | 'weeklyReview',
    patch: Partial<typeof ownership.reminders.checkIn>,
  ) =>
    setOwnership({
      ...ownership,
      reminders: {
        ...ownership.reminders,
        [kind]: { ...ownership.reminders[kind], ...patch },
      },
    });
  return (
    <AppScreen
      title="Reminder Center"
      trailing={<Button title="Done" onPress={goBack} />}
    >
      <SectionCard>
        <Text>
          Notification permission: {permission}. Reminder choices stay saved
          when permission is denied.
        </Text>
        <Text>
          Aurora schedules the next 14 calendar days. Open Aurora to replenish
          reminders. Quiet hours skip reminders without moving them to another
          day. Weekdays refer to the day the notification would appear.
        </Text>
        <Text>No reminders run during onboarding or the walkthrough.</Text>
        <Button
          title="Allow notifications"
          disabled={disabled || busy || permission === 'granted'}
          onPress={async () => {
            setBusy(true);
            setError('');
            try {
              setPermission(
                await syncReminderCenter(
                  ownership,
                  routines,
                  prefs,
                  Date.now(),
                  allowed,
                  true,
                ),
              );
            } catch {
              setError(
                'Could not update reminders. Open Aurora again to retry.',
              );
            } finally {
              setBusy(false);
            }
          }}
        />
        <Button
          title="Open notification settings"
          onPress={() =>
            Linking.openSettings().catch(() =>
              setError('Device settings are unavailable.'),
            )
          }
        />
        {error ? <Text>{error}</Text> : null}
      </SectionCard>
      {REMINDER_KINDS.map((kind) => {
        const enabled =
          kind === 'cutoff'
            ? prefs.notifyCutoff
            : kind === 'windDown'
              ? routines.windDown.enabled
              : ownership.reminders[kind].enabled;
        return (
          <SectionCard key={kind}>
            <Text>
              {labels[kind]} reminder · {enabled ? 'On' : 'Off'}
            </Text>
            <Button
              title={`${enabled ? 'Disable' : 'Enable'} ${labels[kind]} reminder`}
              disabled={disabled}
              onPress={() => {
                if (kind === 'cutoff') setPrefs({ notifyCutoff: !enabled });
                else if (kind === 'windDown')
                  setSleepRoutines({
                    windDown: { ...routines.windDown, enabled: !enabled },
                  });
                else update(kind, { enabled: !enabled });
              }}
            />
            {kind === 'cutoff' ? (
              <StepperField
                disabled={disabled}
                label="Cutoff hour"
                value={prefs.cutoffHour}
                min={0}
                max={23}
                step={1}
                formatValue={(v) => clock(v * 60)}
                onChange={(v) => {
                  if (!disabled) setPrefs({ cutoffHour: v });
                }}
              />
            ) : kind === 'windDown' ? (
              <StepperField
                disabled={disabled}
                label="Minutes before bedtime"
                value={routines.windDown.leadMinutes}
                min={0}
                max={180}
                step={5}
                onChange={(v) => {
                  if (!disabled)
                    setSleepRoutines({
                      windDown: { ...routines.windDown, leadMinutes: v },
                    });
                }}
              />
            ) : (
              <StepperField
                disabled={disabled}
                label={`${labels[kind]} time`}
                value={ownership.reminders[kind].minute}
                min={0}
                max={1439}
                step={15}
                formatValue={clock}
                onChange={(v) => {
                  if (!disabled) update(kind, { minute: v });
                }}
              />
            )}
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
              {days.map((name, day) => (
                <Button
                  key={name}
                  title={`${name}: ${ownership.reminders[kind].weekdays.includes(day) ? 'On' : 'Off'}`}
                  accessibilityLabel={`${labels[kind]} ${name}`}
                  accessibilityValue={{
                    text: ownership.reminders[kind].weekdays.includes(day)
                      ? 'Selected'
                      : 'Not selected',
                  }}
                  disabled={disabled}
                  onPress={() =>
                    setOwnership({
                      ...ownership,
                      reminders: {
                        ...ownership.reminders,
                        [kind]: {
                          ...ownership.reminders[kind],
                          weekdays: ownership.reminders[kind].weekdays.includes(
                            day,
                          )
                            ? ownership.reminders[kind].weekdays.filter(
                                (x) => x !== day,
                              )
                            : [
                                ...ownership.reminders[kind].weekdays,
                                day,
                              ].sort(),
                        },
                      },
                    })
                  }
                />
              ))}
            </View>
          </SectionCard>
        );
      })}
      <SectionCard>
        <Text>
          Quiet hours · {ownership.reminders.quiet.enabled ? 'On' : 'Off'}
        </Text>
        <Button
          title={`${ownership.reminders.quiet.enabled ? 'Disable' : 'Enable'} quiet hours`}
          disabled={disabled}
          onPress={() =>
            setOwnership({
              ...ownership,
              reminders: {
                ...ownership.reminders,
                quiet: {
                  ...ownership.reminders.quiet,
                  enabled: !ownership.reminders.quiet.enabled,
                },
              },
            })
          }
        />
        {(['start', 'end'] as const).map((key) => (
          <StepperField
            disabled={disabled}
            key={key}
            label={`Quiet hours ${key}`}
            value={ownership.reminders.quiet[key]}
            min={0}
            max={1439}
            step={15}
            formatValue={clock}
            onChange={(v) => {
              if (!disabled)
                setOwnership({
                  ...ownership,
                  reminders: {
                    ...ownership.reminders,
                    quiet: { ...ownership.reminders.quiet, [key]: v },
                  },
                });
            }}
          />
        ))}
        <Text>
          End earlier than start crosses midnight. Equal start and end silences
          the entire day.
        </Text>
      </SectionCard>
    </AppScreen>
  );
}
