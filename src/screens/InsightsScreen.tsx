import React, { useMemo, useState } from 'react';
import { Share, Text, View } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import {
  HealthChartCard,
  HealthEmptyState,
  HealthGroupedList,
  HealthHighlightCard,
  HealthRangeControl,
} from '~/components/health';
import { ListRow, SectionCard } from '~/components/ui';
import {
  DEFAULT_INSIGHTS_RANGE,
  getInsightsPresentation,
  type InsightsRange,
} from '~/features/insights/presentation';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useAppScheme from '~/hooks/useAppScheme';
import useSleepGuidance from '~/hooks/useSleepGuidance';
import { navigate } from '~/navigation';
import { makeDailyTotalsCSV, makeSummaryText } from '~/services/storage/export';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { spacing, typeRamp } from '~/theme/tokens';

function formatClock(timestamp: number) {
  return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(timestamp));
}

function InsightsBars({ points }: { points: ReturnType<typeof getInsightsPresentation>['points'] }) {
  const palette = getAppPalette(useAppScheme());
  const maximum = Math.max(1, ...points.map((point) => point.mg ?? 0));
  return (
    <View accessibilityElementsHidden style={{ height: 112, flexDirection: 'row', alignItems: 'flex-end', gap: 3 }}>
      {points.map((point) => (
        <View
          key={point.date}
          style={{
            flex: 1,
            minHeight: 3,
            height: point.mg === null ? 3 : Math.max(7, Math.min(112, (point.mg / maximum) * 112)),
            borderRadius: 2,
            backgroundColor: point.mg === null ? palette.separator : palette.tint,
          }}
        />
      ))}
    </View>
  );
}

export default function InsightsScreen() {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const layout = useAdaptiveLayout();
  const doses = useStore((state) => state.doses);
  const vigilanceSessions = useStore((state) => state.vigilanceSessions);
  const dailyLimit = useStore((state) => state.prefs.dailyLimitMg ?? 400);
  const [range, setRange] = useState<InsightsRange>(DEFAULT_INSIGHTS_RANGE);
  const [shareError, setShareError] = useState<string | undefined>();
  const [exportError, setExportError] = useState<string | undefined>();
  const now = Date.now();
  const presentation = useMemo(
    () => getInsightsPresentation(doses, vigilanceSessions, dailyLimit, range, now),
    [dailyLimit, doses, now, range, vigilanceSessions],
  );
  const sleepGuidance = useSleepGuidance(presentation.current.selected);

  const shareSummary = async () => {
    setShareError(undefined);
    try {
      await Share.share({
        message: makeSummaryText({
          range: `Last ${presentation.days} Days`,
          totalMg: presentation.current.totalMg,
          avgMg: presentation.current.averageMg,
          adherencePct: presentation.adherence.pct,
          streakDays: presentation.adherence.streak,
          dayparts: presentation.dayparts,
          sources: presentation.sourceMix,
        }),
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Share unavailable.';
      setShareError(`Unable to share insights. ${message}`);
    }
  };

  const exportDailyTotals = async () => {
    setExportError(undefined);
    try {
      await Share.share({
        message: makeDailyTotalsCSV(
          presentation.points.map((point) => ({
            date: new Date(point.date).toISOString().slice(0, 10),
            mg: point.mg ?? 0,
          })),
        ),
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Share unavailable.';
      setExportError(`Unable to export insights. ${message}`);
    }
  };

  const chart = (
    <HealthChartCard
      title="Caffeine Intake"
      value={presentation.headline}
      dateRange={presentation.dateRange}
      accessibilitySummary={presentation.accessibilitySummary}
      emptyState={<HealthEmptyState message="No caffeine data for this range." detail="Log a dose to begin a trend." symbol="chart.bar.fill" fallback="stats-chart-outline" />}
    >
      {!presentation.isEmpty ? <InsightsBars points={presentation.points} /> : undefined}
    </HealthChartCard>
  );

  const supporting = (
    <View style={{ gap: spacing.md }}>
      <View style={{ gap: spacing.sm }}>
        <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Highlights</Text>
        <View style={{ flexDirection: layout.isWideLayout ? 'column' : 'row', gap: spacing.sm }}>
          <HealthHighlightCard
            label="Limit Adherence"
            value={`${presentation.adherence.pct}%`}
            detail={`Current streak ${presentation.adherence.streak} day${presentation.adherence.streak === 1 ? '' : 's'}`}
            accentColor={palette.tint}
          />
          <HealthHighlightCard
            label="Trend"
            value={typeof presentation.deltaPct === 'number' ? `${presentation.deltaPct >= 0 ? '+' : ''}${presentation.deltaPct}%` : '—'}
            detail={presentation.deltaLabel}
            accentColor={palette.tint}
          />
        </View>
      </View>

      <View style={{ gap: spacing.sm }}>
        <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Vigilance</Text>
        {presentation.vigilance.latest ? (
          <HealthGroupedList rows={[
            { title: 'Latest score', subtitle: presentation.vigilance.latest.rating, value: `${presentation.vigilance.latest.score}` },
            { title: `${presentation.days}-day average`, subtitle: `${presentation.vigilance.trendSessions.length} session${presentation.vigilance.trendSessions.length === 1 ? '' : 's'} in this range`, value: presentation.vigilance.averageScore === undefined ? '—' : `${presentation.vigilance.averageScore}` },
            { title: 'Baseline', subtitle: presentation.vigilance.hasBaseline ? 'Ready to compare future sessions.' : 'Complete at least three sessions to build a usable attentiveness baseline.', value: presentation.vigilance.hasBaseline ? 'Ready' : 'Building' },
          ]} />
        ) : <HealthEmptyState message="No vigilance sessions in this range." detail="Run the reaction test to build a baseline." />}
        <Button title={presentation.vigilance.latest ? 'Run Again' : 'Start Test'} variant="tinted" onPress={() => navigate('VigilanceTest')} />
      </View>
    </View>
  );

  return (
    <AppScreen
      title="Insights"
      subtitle="Caffeine, sleep, and alertness trends."
      trailing={<Button title="Share" variant="plain" onPress={shareSummary} />}
    >
      <View style={{ gap: spacing.md }}>
        <HealthRangeControl
          accessibilityLabel="Insights range"
          value={range}
          onChange={setRange}
          options={[{ value: '7', label: 'W' }, { value: '14', label: '2W' }, { value: '30', label: 'M' }]}
        />

        <View
          testID={layout.isWideLayout ? 'insights-wide-layout' : 'insights-compact-layout'}
          style={{ flexDirection: layout.isWideLayout ? 'row' : 'column', alignItems: 'flex-start', gap: spacing.xl }}
        >
          <View testID="insights-primary-column" style={{ width: layout.isWideLayout ? layout.leftColumnWidth : '100%', gap: spacing.md }}>
            {chart}
            <View style={{ gap: spacing.sm }}>
              <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Patterns</Text>
              <SectionCard>
                <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Daypart Mix</Text>
                {presentation.dayparts.map((item) => (
                  <ListRow key={item.label} title={item.label} subtitle="Selected range" value={`${Math.round(item.mg)} mg`} />
                ))}
              </SectionCard>
              <SectionCard>
                <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Source Mix</Text>
                {presentation.sourceMix.length ? presentation.sourceMix.map((item) => (
                  <ListRow key={item.label} title={item.label} subtitle={`${item.pct}% of intake`} value={`${item.mg} mg`} />
                )) : <HealthEmptyState message="No logged sources in this range yet." />}
              </SectionCard>
            </View>
          </View>
          <View testID="insights-supporting-column" style={{ width: layout.isWideLayout ? layout.rightColumnWidth : '100%', gap: spacing.md }}>
            {supporting}
          </View>
        </View>

        <View style={{ gap: spacing.sm }}>
          <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Guidance</Text>
          <HealthGroupedList rows={[
            { title: 'Suggested bedtime', subtitle: `Projected active caffeine ${sleepGuidance.mgAtBed} mg`, value: formatClock(sleepGuidance.bedtime) },
            { title: 'Suggested wake', subtitle: '90-minute sleep cycles, aiming for a normal morning window', value: formatClock(sleepGuidance.wake) },
          ]} />
          <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>Guidance uses the same selected range as the trends above.</Text>
        </View>

        <View style={{ gap: spacing.sm }}>
          <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Options</Text>
          <HealthGroupedList rows={[
            { title: 'Show All Data', subtitle: `${doses.length} logged dose${doses.length === 1 ? '' : 's'}`, onPress: () => navigate('CaffeineHistory') },
            { title: 'Export CSV', subtitle: `Daily totals for ${presentation.days} days`, onPress: exportDailyTotals },
          ]} />
          {shareError ? <Text accessibilityRole="alert" style={{ ...typeRamp.footnote, color: palette.destructive }}>{shareError}</Text> : null}
          {exportError ? <Text accessibilityRole="alert" style={{ ...typeRamp.footnote, color: palette.destructive }}>{exportError}</Text> : null}
        </View>
      </View>
    </AppScreen>
  );
}
