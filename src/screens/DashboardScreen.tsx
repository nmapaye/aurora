import React, { useMemo } from 'react';
import { Text, View } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import CaffeineTodayGraph from '~/components/CaffeineTodayGraph';
import {
  HealthAlertCard,
  HealthMetricCard,
  HealthSectionHeader,
  ListRow,
  SectionCard,
  SectionTitle,
} from '~/components/ui';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
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

function fmtDay(ts?: number) {
  if (!ts) return 'Today';
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toDateString();
  }
}

function fmtDuration(ms?: number) {
  if (!ms || ms <= 0) return 'No Data';
  const hours = Math.floor(ms / 3_600_000);
  const minutes = Math.round((ms % 3_600_000) / 60_000);
  return `${hours}h ${minutes}m`;
}

export default function DashboardScreen() {
  const layout = useAdaptiveLayout();
  const { nowScore, mgActiveNow: mgActive } = (useAlertnessSeries() as any) || {};
  const cutoff = useCaffeineCutoff();
  const sleepGuidance = useSleepGuidance();

  const doses = useStore((s) => s.doses);
  const sleepCount = useStore((s) => s.sleeps.length);
  const latestSleep = useStore((s) =>
    [...s.sleeps].sort((a, b) => b.end - a.end)[0]
  );
  const latestVigilanceSession = useStore((s) => s.vigilanceSessions[0]);
  const addDose = useStore((s) => s.addDose);
  const demoMode = useStore((s) => s.demoMode);
  const loadDemoData = useStore((s) => s.loadDemoData);

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

  const alertCard =
    demoMode || todaySummary.recent.length === 0 ? (
      <HealthAlertCard
        tone={demoMode ? 'info' : 'warning'}
        label={demoMode ? 'Reviewer Data' : 'Fresh Install'}
        dateLabel={fmtDay(Date.now())}
        icon={demoMode ? 'sparkles-outline' : 'alert-circle-outline'}
        title={demoMode ? 'Sample flow is ready.' : 'No data yet.'}
        body={
          demoMode
            ? 'Sleep, caffeine, and vigilance are seeded.'
            : 'Log caffeine or load reviewer data to fill Summary.'
        }
        actionLabel={demoMode ? 'More Details' : 'Load Sample'}
        onAction={
          demoMode
            ? () => navigate('Insights', { section: 'summary' })
            : loadDemoData
        }
      />
    ) : null;

  const pinnedCards = (
    <>
      <HealthSectionHeader title="Pinned" actionLabel="Edit" />
      <View style={{ gap: 18 }}>
        <HealthMetricCard
          icon="cafe"
          label="Caffeine"
          labelColor="#0A84FF"
          dateLabel="Today"
          value={`${Math.round(todaySummary.todayTotal)} mg`}
          detail={todaySummary.deltaText}
          onPress={() => navigate('Insights', { section: 'summary' })}
        />
        <HealthMetricCard
          icon="pulse"
          label="Active Caffeine"
          labelColor="#32D74B"
          dateLabel="Now"
          value={`${Math.round(mgActive ?? 0)} mg`}
          detail={`Alertness ${Math.round(nowScore ?? 0)}`}
          onPress={() => navigate('Insights', { section: 'trends' })}
        />
        <HealthMetricCard
          icon="bed"
          label="Sleep"
          labelColor="#7D7AFF"
          dateLabel={fmtDay(latestSleep?.end)}
          value={latestSleep ? fmtDuration(latestSleep.end - latestSleep.start) : 'No Data'}
          detail={
            latestSleep
              ? `${sleepCount} session${sleepCount === 1 ? '' : 's'} available`
              : 'Connect Health or use demo data'
          }
          onPress={() => navigate('Sleep')}
        />
        <HealthMetricCard
          icon="speedometer"
          label="Vigilance"
          labelColor="#30D5C8"
          dateLabel={latestVigilanceSession ? fmtDay(latestVigilanceSession.completedAt) : 'Today'}
          value={
            latestVigilanceSession
              ? `${latestVigilanceSession.score}`
              : 'No Data'
          }
          detail={
            latestVigilanceSession
              ? `${latestVigilanceSession.rating} • ${latestVigilanceSession.medianReactionMs ?? '—'} ms median`
              : 'Run a 60-second test'
          }
          onPress={() => navigate('VigilanceTest')}
        />
        <HealthMetricCard
          icon="moon"
          label="Caffeine Cutoff"
          labelColor="#BF5AF2"
          dateLabel="Today"
          value={fmtTime(cutoff?.nextCutoff)}
          detail={`Bed ${fmtTime(sleepGuidance?.bedtime)} • Wake ${fmtTime(sleepGuidance?.wake)}`}
          onPress={() => navigate('Sleep')}
        />
      </View>
    </>
  );

  const logSection = (
    <>
      <SectionTitle>Log</SectionTitle>
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
              variant="plain"
              onPress={() => quickAdd(mg as number, label as string)}
            />
          ))}
        </View>
        <Button title="Custom Entry" variant="plain" onPress={() => navigate('Log')} />
      </SectionCard>
    </>
  );

  const recentSection = (
    <>
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
    </>
  );

  const todayPanel = (
    <SectionCard style={{ borderRadius: 28, padding: 20, gap: 18 }}>
      <HealthSectionHeader
        title="Today"
        actionLabel="Details"
        onAction={() => navigate('Insights', { section: 'summary' })}
      />
      <CaffeineTodayGraph
        height={340}
        showCaption={false}
        compact
        variant="panel"
      />
      <View style={{ gap: 2 }}>
        <ListRow
          title="Caffeine"
          subtitle={todaySummary.deltaText}
          value={`${Math.round(todaySummary.todayTotal)} mg`}
        />
        <ListRow
          title="Active now"
          subtitle={`Alertness ${Math.round(nowScore ?? 0)}`}
          value={`${Math.round(mgActive ?? 0)} mg`}
        />
        <ListRow
          title="Cutoff"
          subtitle={`Bed ${fmtTime(sleepGuidance?.bedtime)}`}
          value={fmtTime(cutoff?.nextCutoff)}
        />
        <ListRow
          title="Vigilance"
          subtitle={
            latestVigilanceSession
              ? `${latestVigilanceSession.rating} • ${latestVigilanceSession.medianReactionMs ?? '—'} ms median`
              : 'No session yet'
          }
          value={
            latestVigilanceSession ? `${latestVigilanceSession.score}` : '—'
          }
        />
      </View>
    </SectionCard>
  );

  return (
    <AppScreen title="Summary">
      {layout.isWideLayout ? (
        <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 24 }}>
          <View style={{ width: layout.leftColumnWidth, gap: 18 }}>
            {alertCard}
            {pinnedCards}
            {logSection}
            {recentSection}
          </View>
          <View style={{ width: layout.rightColumnWidth, gap: 18 }}>
            {todayPanel}
          </View>
        </View>
      ) : (
        <>
          {alertCard}
          {pinnedCards}
          {logSection}
          {recentSection}
        </>
      )}
    </AppScreen>
  );
}
