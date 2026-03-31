import React, { useMemo } from 'react';
import { Text, View } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { ListRow, SectionCard, SectionTitle, StatTile } from '~/components/ui';
import { useAlertnessSeries } from '~/hooks/useAlertnessSeries';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';
import useSleepGuidance from '~/hooks/useSleepGuidance';
import { navigate } from '~/navigation';
import { useStore } from '~/state/store';

function fmtTime(ts?: number) {
  if (!ts) return '—';
  try {
    return new Intl.DateTimeFormat(undefined, {
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toLocaleTimeString();
  }
}

function fmtDateTime(ts: number) {
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toLocaleString();
  }
}

export default function DashboardScreen() {
  const { nowScore, mgActiveNow: mgActive } = (useAlertnessSeries() as any) || {};
  const cutoff = useCaffeineCutoff();
  const sleepGuidance = useSleepGuidance();

  const doses = useStore((s) => s.doses);
  const latestVigilanceSession = useStore((s) => s.vigilanceSessions[0]);
  const addDose = useStore((s) => s.addDose);

  const todaySummary = useMemo(() => {
    const now = new Date();
    const key = (value: Date) =>
      `${value.getFullYear()}-${value.getMonth()}-${value.getDate()}`;
    const todayKey = key(now);
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayKey = key(yesterday);

    let todayTotal = 0;
    let yesterdayTotal = 0;
    const recent = [...doses]
      .filter((dose) => {
        const doseKey = key(new Date(dose.timestamp));
        if (doseKey === todayKey) {
          todayTotal += dose.mg;
          return true;
        }
        if (doseKey === yesterdayKey) {
          yesterdayTotal += dose.mg;
        }
        return false;
      })
      .sort((a, b) => b.timestamp - a.timestamp)
      .slice(0, 4);

    const delta = todayTotal - yesterdayTotal;
    const deltaText = `${delta >= 0 ? '+' : ''}${delta} mg vs yesterday`;
    return { todayTotal, deltaText, recent };
  }, [doses]);

  const quickAdd = (mg: number, source: string) => {
    const id = `${Date.now().toString(36)}-${Math.random()
      .toString(36)
      .slice(2)}`;
    addDose({ id, timestamp: Date.now(), mg, source });
  };

  return (
    <AppScreen
      title="Today"
      subtitle="A calmer snapshot of caffeine, vigilance, and the sleep you’re trying to protect."
    >
      <SectionTitle>Overview</SectionTitle>
      <View style={{ flexDirection: 'row', gap: 12 }}>
        <StatTile
          label="Caffeine"
          value={`${Math.round(todaySummary.todayTotal)} mg`}
          detail={todaySummary.deltaText}
        />
        <StatTile
          label="Active now"
          value={`${Math.round(mgActive ?? 0)} mg`}
          detail={`Alertness ${Math.round(nowScore ?? 0)}`}
        />
      </View>

      <SectionTitle>Quick Add</SectionTitle>
      <SectionCard>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
          {[
            ['Espresso', 60],
            ['Drip', 95],
            ['Matcha', 70],
            ['Energy', 160],
          ].map(([label, mg]) => (
            <Button
              key={label}
              title={`${label} ${mg}mg`}
              variant="secondary"
              onPress={() => quickAdd(mg as number, label as string)}
            />
          ))}
        </View>
        <Button title="Custom entry" variant="plain" onPress={() => navigate('Log')} />
      </SectionCard>

      <SectionTitle
        action={<Button title="Start test" variant="secondary" onPress={() => navigate('VigilanceTest')} />}
      >
        Vigilance
      </SectionTitle>
      <SectionCard>
        <StatTile
          label="Latest session"
          value={
            latestVigilanceSession
              ? `${latestVigilanceSession.score} ${latestVigilanceSession.rating}`
              : 'No baseline'
          }
          detail={
            latestVigilanceSession?.medianReactionMs
              ? `Median reaction ${latestVigilanceSession.medianReactionMs} ms`
              : 'Run the 60-second reaction task to start tracking attentiveness.'
          }
        />
      </SectionCard>

      <SectionTitle>Recommendations</SectionTitle>
      <SectionCard>
        <ListRow
          title="Daily cutoff"
          subtitle="Simple late-day caffeine guardrail."
          value={fmtTime(cutoff?.nextCutoff)}
        />
        <ListRow
          title="Suggested bedtime"
          subtitle="Estimated from active caffeine and your current target."
          value={fmtTime(sleepGuidance?.bedtime)}
        />
        <ListRow
          title="Suggested wake"
          subtitle="Based on 90-minute cycles and your current bedtime target."
          value={fmtTime(sleepGuidance?.wake)}
        />
      </SectionCard>

      <SectionTitle
        action={
          <Button
            title="See history"
            variant="plain"
            onPress={() => navigate('Insights', { section: 'history' })}
          />
        }
      >
        Recent activity
      </SectionTitle>
      <SectionCard>
        {todaySummary.recent.length === 0 ? (
          <Text style={{ fontSize: 15, lineHeight: 20, color: '#8E8E93' }}>
            No doses logged today. Use Quick Add or Custom entry to capture your first intake.
          </Text>
        ) : (
          todaySummary.recent.map((dose) => (
            <ListRow
              key={dose.id}
              title={`${dose.mg} mg${dose.source ? ` • ${dose.source}` : ''}`}
              subtitle={fmtDateTime(dose.timestamp)}
            />
          ))
        )}
      </SectionCard>
    </AppScreen>
  );
}
