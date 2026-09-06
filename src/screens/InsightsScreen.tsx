import ChartTable from '~/components/ChartTable';
import MetricExplanation from '~/features/insights/MetricExplanation';
import useNow from '~/hooks/useNow';
import React, { useMemo, useRef, useState } from 'react';
import { ScrollView, Share, Text, View } from 'react-native';

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
import {
  AppWalkthroughCoach,
  useAppWalkthrough,
  WalkthroughReveal,
} from '~/features/appWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useAppScheme from '~/hooks/useAppScheme';
import useSleepGuidance from '~/hooks/useSleepGuidance';
import { navigate } from '~/navigation';
import {
  formatLocalDate,
  makeDailyTotalsCSV,
  makeSummaryText,
} from '~/services/storage/export';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { spacing, typeRamp } from '~/theme/tokens';

function formatClock(timestamp: number) {
  return new Intl.DateTimeFormat(undefined, {
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(timestamp));
}

function InsightsBars({
  points,
}: {
  points: ReturnType<typeof getInsightsPresentation>['points'];
}) {
  const palette = getAppPalette(useAppScheme());
  const maximum = Math.max(1, ...points.map((point) => point.mg ?? 0));
  return (
    <View
      accessibilityElementsHidden
      style={{
        height: 112,
        flexDirection: 'row',
        alignItems: 'flex-end',
        gap: 3,
      }}
    >
      {points.map((point) => (
        <View
          key={point.date}
          style={{
            flex: 1,
            minHeight: 3,
            height:
              point.mg === null
                ? 3
                : Math.max(7, Math.min(112, (point.mg / maximum) * 112)),
            borderRadius: 2,
            backgroundColor:
              point.mg === null ? palette.separator : palette.tint,
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
  const zeroDays = useStore((s) => s.caffeine.zeroDays);
  const doses = useStore((state) => state.doses);
  const vigilanceSessions = useStore((state) => state.vigilanceSessions);
  const dailyLimit = useStore((state) => state.prefs.dailyLimitMg ?? 400);
  const [range, setRange] = useState<InsightsRange>(DEFAULT_INSIGHTS_RANGE);
  const [shareError, setShareError] = useState<string | undefined>();
  const [exportError, setExportError] = useState<string | undefined>();
  const scrollRef = useRef<ScrollView>(null);
  const contentRef = useRef<View>(null);
  const highlightsAnchorRef = useRef<View>(null);
  const walkthrough = useAppWalkthrough({
    route: 'Insights',
    isWideLayout: layout.isWideLayout,
    scrollRef,
    contentRef,
  });
  const now = useNow();
  const presentation = useMemo(
    () =>
      getInsightsPresentation(
        doses,
        vigilanceSessions,
        dailyLimit,
        range,
        now,
        zeroDays,
      ),
    [dailyLimit, doses, now, range, vigilanceSessions, zeroDays],
  );
  const sleepGuidance = useSleepGuidance(
    doses.filter((d) => !d.id.startsWith('demo:') && d.timestamp <= now),
  );

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
      const message =
        error instanceof Error ? error.message : 'Share unavailable.';
      setShareError(`Unable to share insights. ${message}`);
    }
  };

  const exportDailyTotals = async () => {
    setExportError(undefined);
    try {
      await Share.share({
        message: makeDailyTotalsCSV(
          presentation.points.map((point) => ({
            date: formatLocalDate(point.date),
            mg: point.mg ?? 0,
          })),
        ),
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'Share unavailable.';
      setExportError(`Unable to export insights. ${message}`);
    }
  };

  const chart = (
    <HealthChartCard
      title="Caffeine Intake"
      value={presentation.headline}
      dateRange={presentation.dateRange}
      accessibilitySummary={presentation.accessibilitySummary}
      emptyState={
        <HealthEmptyState
          message="No caffeine data for this range."
          detail="Log a dose to begin a trend."
          symbol="chart.bar.fill"
          fallback="stats-chart-outline"
        />
      }
    >
      {!presentation.isEmpty ? (
        <View style={{ gap: spacing.xs }}>
          <InsightsBars points={presentation.points} />
          <ChartTable title="caffeine intake" rows={presentation.points.map(p=>`${new Date(p.date).toLocaleDateString()}: ${p.mg===null?'Missing caffeine records':`${p.mg.toFixed(0)} mg recorded caffeine`}`)} />
          <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>
            Average uses recorded days, including confirmed caffeine-free days.
            Missing days are excluded.
          </Text>
        </View>
      ) : undefined}
    </HealthChartCard>
  );

  const supporting = (
    <View style={{ gap: spacing.md }}>
      <View style={{ gap: spacing.sm }}>
        <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>
          Highlights
        </Text>
        <View
          style={{
            flexDirection: layout.isWideLayout ? 'column' : 'row',
            gap: spacing.sm,
          }}
        >
          <HealthHighlightCard
            label="Limit Adherence"
            value={`${presentation.adherence.pct}%`}
            detail={`Current streak ${presentation.adherence.streak} day${presentation.adherence.streak === 1 ? '' : 's'}`}
            accentColor={palette.tint}
          />
          <HealthHighlightCard
            label="Trend"
            value={
              typeof presentation.deltaPct === 'number'
                ? `${presentation.deltaPct >= 0 ? '+' : ''}${presentation.deltaPct}%`
                : '—'
            }
            detail={presentation.deltaLabel}
            accentColor={palette.tint}
          />
        </View>
      </View>

      <View style={{ gap: spacing.sm }}>
        <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>
          Vigilance
        </Text>
        {presentation.vigilance.latest ? (
          <HealthGroupedList
            rows={[
              {
                title: 'Latest score',
                subtitle: presentation.vigilance.latest.rating,
                value: `${presentation.vigilance.latest.score}`,
              },
              {
                title: `${presentation.days}-day average`,
                subtitle: `${presentation.vigilance.trendSessions.length} session${presentation.vigilance.trendSessions.length === 1 ? '' : 's'} in this range`,
                value:
                  presentation.vigilance.averageScore === undefined
                    ? '—'
                    : `${presentation.vigilance.averageScore}`,
              },
              {
                title: 'Baseline',
                subtitle: presentation.vigilance.hasBaseline
                  ? 'Ready to compare future sessions.'
                  : 'Complete at least three sessions to build a usable attentiveness baseline.',
                value: presentation.vigilance.hasBaseline
                  ? 'Ready'
                  : 'Building',
              },
            ]}
          />
        ) : (
          <HealthEmptyState
            message="No vigilance sessions in this range."
            detail="Run the reaction test to build a baseline."
          />
        )}
        <Button
          title={presentation.vigilance.latest ? 'Run Again' : 'Start Test'}
          variant="tinted"
          onPress={() => navigate('VigilanceTest')}
        />
      </View>
    </View>
  );

  const walkthroughCoach = walkthrough.active ? (
    <WalkthroughReveal
      key={walkthrough.step.id}
      active
      revealed={walkthrough.coachVisible}
      reduceMotion={walkthrough.reduceMotion}
    >
      <AppWalkthroughCoach
        step={walkthrough.step}
        locked={walkthrough.locked}
        headingRef={walkthrough.coachHeadingRef}
        onLayout={walkthrough.onCoachLayout}
        onSkip={walkthrough.onSkip}
        onPrimary={walkthrough.onPrimary}
      />
    </WalkthroughReveal>
  ) : null;

  return (
    <AppScreen
      title="Insights"
      subtitle="Caffeine, sleep, and alertness trends."
      trailing={<Button title="Share" variant="plain" onPress={shareSummary} />}
      scrollRef={scrollRef}
      contentRef={contentRef}
      scrollEnabled={!walkthrough.active}
      interactionEnabled={!walkthrough.active}
      bottomOverlay={walkthroughCoach}
      onScroll={walkthrough.onScroll}
      onViewportLayout={walkthrough.onViewportLayout}
      headerTransform={(header) => (
        <WalkthroughReveal
          active={walkthrough.active}
          revealed={walkthrough.isRevealed('insights-header')}
          reduceMotion={walkthrough.reduceMotion}
        >
          {header}
        </WalkthroughReveal>
      )}
    >
      <View style={{ gap: spacing.md }}>
        <WalkthroughReveal
          active={walkthrough.active}
          revealed={walkthrough.isRevealed('insights-range')}
          reduceMotion={walkthrough.reduceMotion}
        >
          <HealthRangeControl
            accessibilityLabel="Insights range"
            value={range}
            onChange={setRange}
            options={[
              { value: '7', label: 'W' },
              { value: '14', label: '2W' },
              { value: '30', label: 'M' },
            ]}
          />
        </WalkthroughReveal>

        <View
          testID={
            layout.isWideLayout
              ? 'insights-wide-layout'
              : 'insights-compact-layout'
          }
          style={{
            flexDirection: layout.isWideLayout ? 'row' : 'column',
            alignItems: 'flex-start',
            gap: spacing.xl,
          }}
        >
          <WalkthroughReveal
            active={walkthrough.active}
            revealed={walkthrough.isRevealed('insights-range')}
            reduceMotion={walkthrough.reduceMotion}
            style={{
              width: layout.isWideLayout ? layout.leftColumnWidth : '100%',
            }}
          >
            <View
              testID="insights-primary-column"
              style={{
                width: layout.isWideLayout ? layout.leftColumnWidth : '100%',
                gap: spacing.md,
              }}
            >
              {chart}
              <View style={{ gap: spacing.sm }}>
                <Text
                  style={{ ...typeRamp.headline, color: palette.textPrimary }}
                >
                  Patterns
                </Text>
                <SectionCard>
                  <Text
                    style={{ ...typeRamp.headline, color: palette.textPrimary }}
                  >
                    Daypart Mix
                  </Text>
                  {presentation.dayparts.map((item) => (
                    <ListRow
                      key={item.label}
                      title={item.label}
                      subtitle="Selected range"
                      value={`${Math.round(item.mg)} mg`}
                    />
                  ))}
                </SectionCard>
                <SectionCard>
                  <Text
                    style={{ ...typeRamp.headline, color: palette.textPrimary }}
                  >
                    Source Mix
                  </Text>
                  {presentation.sourceMix.length ? (
                    presentation.sourceMix.map((item) => (
                      <ListRow
                        key={item.label}
                        title={item.label}
                        subtitle={`${item.pct}% of intake`}
                        value={`${item.mg} mg`}
                      />
                    ))
                  ) : (
                    <HealthEmptyState message="No logged sources in this range yet." />
                  )}
                </SectionCard>
              </View>
            </View>
          </WalkthroughReveal>
          <WalkthroughReveal
            active={walkthrough.active}
            revealed={walkthrough.isRevealed('insights-highlights')}
            reduceMotion={walkthrough.reduceMotion}
            style={{
              width: layout.isWideLayout ? layout.rightColumnWidth : '100%',
            }}
          >
            <View
              ref={highlightsAnchorRef}
              collapsable={false}
              onLayout={() =>
                walkthrough.measureAnchor(
                  'insights-highlights',
                  highlightsAnchorRef.current,
                )
              }
              testID="insights-supporting-column"
              style={{
                width: layout.isWideLayout ? layout.rightColumnWidth : '100%',
                gap: spacing.md,
              }}
            >
              {supporting}
            </View>
          </WalkthroughReveal>
        </View>

        <WalkthroughReveal
          active={walkthrough.active}
          revealed={walkthrough.isRevealed('insights-highlights')}
          reduceMotion={walkthrough.reduceMotion}
          style={{ gap: spacing.md }}
        >
          <View style={{ gap: spacing.sm }}>
            <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>
              Guidance
            </Text>
            <HealthGroupedList
              rows={[
                {
                  title: 'Planned bedtime',
                  subtitle: `Projected active caffeine ${sleepGuidance.mgAtBed} mg`,
                  value: formatClock(sleepGuidance.bedtime),
                },
                {
                  title: 'Planned wake',
                  subtitle: 'Your weekly schedule, including date exceptions',
                  value: formatClock(sleepGuidance.wake),
                },
              ]}
            />
            <Text
              style={{ ...typeRamp.footnote, color: palette.textSecondary }}
            >
              Bedtime estimates use all recorded personal doses through now and
              your shared sleep schedule.
            </Text>
          </View>

          <View style={{ gap: spacing.sm }}>
            <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>
              Options
            </Text>
            <HealthGroupedList
              rows={[
                {
                  title: 'Show All Data',
                  subtitle: `${doses.length} logged dose${doses.length === 1 ? '' : 's'}`,
                  onPress: () => navigate('CaffeineHistory'),
                },
                {
                  title: 'Export CSV',
                  subtitle: `Daily totals for ${presentation.days} days`,
                  onPress: exportDailyTotals,
                },
              ]}
            />
            {shareError ? (
              <Text
                accessibilityRole="alert"
                style={{ ...typeRamp.footnote, color: palette.destructive }}
              >
                {shareError}
              </Text>
            ) : null}
            {exportError ? (
              <Text
                accessibilityRole="alert"
                style={{ ...typeRamp.footnote, color: palette.destructive }}
              >
                {exportError}
              </Text>
            ) : null}
          </View>
        </WalkthroughReveal>
      </View>
      {!walkthrough.active ? (
        <>
          <Button
            title="Explore timeline, patterns, and weekly review"
            onPress={() => navigate('InsightsExplorer')}
          />
          <MetricExplanation metric="adherence" />
          <MetricExplanation metric="weekday" />
          <MetricExplanation metric="vigilance" />
          <MetricExplanation metric="caffeine" />
          <Button
            title="Caffeine planning and targets"
            onPress={() => navigate('Planning')}
          />
          <Button
            title="Check-ins and experiments"
            onPress={() => navigate('Experiments')}
          />
        </>
      ) : null}
    </AppScreen>
  );
}
