import React, { useMemo, useRef, useState } from 'react';
import { ScrollView, Text, View } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import SignalCard from '~/components/SignalCard';
import {
  HealthBarChart,
  HealthChartCard,
  HealthEmptyState,
  HealthGroupedList,
  HealthRangeControl,
} from '~/components/health';
import {
  DEFAULT_INSIGHTS_RANGE,
  describeInsightsChartDay,
  getInsightsPresentation,
  type InsightsRange,
  type InsightsTrend,
} from '~/features/insights/presentation';
import {
  AppWalkthroughCoach,
  useAppWalkthrough,
  WalkthroughReveal,
} from '~/features/appWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useNow from '~/hooks/useNow';
import useAppScheme from '~/hooks/useAppScheme';
import { navigate } from '~/navigation';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, radii, spacing, typeRamp } from '~/theme/tokens';

const shortDay = (time: number) =>
  new Date(time).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });

// Shown only when both periods have enough recorded days; otherwise a quiet
// line says what a comparison still needs.
function TrendNote({ trend }: { trend: InsightsTrend }) {
  const palette = getAppPalette(useAppScheme());
  if (trend.status === 'insufficient') {
    return (
      <Text
        testID="insights-trend-insufficient"
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...typeRamp.footnote, color: palette.textTertiary }}
      >
        {trend.text}
      </Text>
    );
  }
  return (
    <View
      testID="insights-trend"
      accessible
      accessibilityLabel={`Compared with the previous period, ${trend.text}. ${trend.detail}`}
      style={{ gap: 2, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderRadius: radii.card, borderWidth: 1, borderColor: palette.cardBorder }}
    >
      <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.subheadline, fontWeight: '600', color: palette.textPrimary }}>
        {trend.text}
      </Text>
      <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.footnote, color: palette.textSecondary }}>
        {trend.detail}
      </Text>
    </View>
  );
}

export default function InsightsScreen() {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const layout = useAdaptiveLayout();
  const doses = useStore((state) => state.doses);
  const vigilanceSessions = useStore((state) => state.vigilanceSessions);
  const [range, setRange] = useState<InsightsRange>(DEFAULT_INSIGHTS_RANGE);
  const [showDetails, setShowDetails] = useState(false);
  const scrollRef = useRef<ScrollView>(null);
  const contentRef = useRef<View>(null);
  const reactionAnchorRef = useRef<View>(null);
  const walkthrough = useAppWalkthrough({
    route: 'Insights',
    isWideLayout: layout.isWideLayout,
    scrollRef,
    contentRef,
  });
  const now = useNow();
  const presentation = useMemo(
    () => getInsightsPresentation(doses, vigilanceSessions, range, now),
    [doses, now, range, vigilanceSessions],
  );
  const { reaction } = presentation;
  const maxMg = Math.max(0, ...presentation.points.map((point) => point.mg ?? 0));

  const chart = (
    <HealthChartCard
      title="Caffeine Intake"
      value={presentation.headline}
      dateRange={presentation.source ? `${presentation.period} · ${presentation.source}` : presentation.period}
      accessibilitySummary={presentation.accessibilitySummary}
      interactiveChildren
      emptyState={<HealthEmptyState message="No caffeine recorded in this range." detail="Days without entries show as no record." symbol="chart.bar.fill" fallback="stats-chart-outline" />}
    >
      {!presentation.isEmpty ? (
        <HealthBarChart
          testID="insights-bars"
          height={layout.isWideLayout ? 140 : 112}
          points={presentation.points.map((point) => ({ key: point.date, value: point.mg }))}
          max={maxMg}
          color={palette.caffeineAccent}
          startLabel={shortDay(presentation.points[0].date)}
          endLabel="Today"
          inspection={{
            accessibilityLabel: presentation.accessibilitySummary,
            defaultIndex: presentation.latestRecordedIndex,
            describe: (index) => describeInsightsChartDay(presentation.points[index]),
          }}
        />
      ) : undefined}
    </HealthChartCard>
  );

  const details = (
    <View testID="insights-details" style={{ gap: spacing.sm }}>
      <HealthGroupedList rows={[{
        title: 'Details',
        subtitle: 'Time of day, drinks, and all entries',
        accessibilityLabel: 'Details, time of day, drinks, and all entries',
        accessibilityHint: showDetails ? 'Hides the breakdowns' : 'Shows the breakdowns for this range',
        expanded: showDetails,
        onPress: () => setShowDetails((visible) => !visible),
      }]} />
      {showDetails ? (
        <View testID="insights-details-panel" style={{ gap: spacing.sm }}>
          <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.footnote, color: palette.textSecondary }}>
            Totals of recorded entries · {presentation.dateRange}
          </Text>
          {presentation.isEmpty ? (
            <HealthEmptyState message="No entries in this range." />
          ) : (
            <>
              <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Time of Day</Text>
              <HealthGroupedList rows={presentation.dayparts.map((item) => ({
                title: item.label,
                subtitle: item.entries ? `${item.entries} ${item.entries === 1 ? 'entry' : 'entries'}` : 'No entries',
                value: item.entries ? `${Math.round(item.mg)} mg` : '—',
              }))} />
              <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Drinks</Text>
              <HealthGroupedList rows={presentation.drinkMix.map((item) => ({
                title: item.label,
                subtitle: `${item.pct}% of recorded caffeine`,
                value: `${Math.round(item.mg)} mg`,
              }))} />
            </>
          )}
          <HealthGroupedList rows={[{
            title: 'Show All Caffeine Data',
            subtitle: `${doses.length} ${doses.length === 1 ? 'entry' : 'entries'}`,
            accessibilityLabel: `Show All Caffeine Data, ${doses.length} ${doses.length === 1 ? 'entry' : 'entries'}`,
            accessibilityHint: 'Opens caffeine history',
            onPress: () => navigate('CaffeineHistory'),
          }]} />
        </View>
      ) : null}
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
      subtitle="What you recorded over time."
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
        <WalkthroughReveal active={walkthrough.active} revealed={walkthrough.isRevealed('insights-range')} reduceMotion={walkthrough.reduceMotion}>
          <HealthRangeControl
            accessibilityLabel="Insights range"
            value={range}
            onChange={setRange}
            options={[{ value: '7', label: 'W', accessibilityLabel: 'Week' }, { value: '14', label: '2W', accessibilityLabel: 'Two weeks' }, { value: '30', label: 'M', accessibilityLabel: 'Month' }]}
          />
        </WalkthroughReveal>

        <View
          testID={layout.isWideLayout ? 'insights-wide-layout' : 'insights-compact-layout'}
          style={{ flexDirection: layout.isWideLayout ? 'row' : 'column', alignItems: 'flex-start', gap: spacing.xl }}
        >
          <WalkthroughReveal active={walkthrough.active} revealed={walkthrough.isRevealed('insights-range')} reduceMotion={walkthrough.reduceMotion} style={{ width: layout.isWideLayout ? layout.leftColumnWidth : '100%' }}>
            <View testID="insights-primary-column" style={{ width: layout.isWideLayout ? layout.leftColumnWidth : '100%', gap: spacing.sm }}>
              {chart}
              <TrendNote trend={presentation.trend} />
            </View>
          </WalkthroughReveal>
          <WalkthroughReveal active={walkthrough.active} revealed={walkthrough.isRevealed('insights-reaction')} reduceMotion={walkthrough.reduceMotion} style={{ width: layout.isWideLayout ? layout.rightColumnWidth : '100%' }}>
            <View ref={reactionAnchorRef} collapsable={false} onLayout={() => walkthrough.measureAnchor('insights-reaction', reactionAnchorRef.current)} testID="insights-supporting-column" style={{ width: layout.isWideLayout ? layout.rightColumnWidth : '100%', gap: spacing.sm }}>
              <SignalCard
                model={reaction}
                icon="speedometer"
                accent={palette.tint}
                onPress={() => navigate('VigilanceTest')}
              />
              {reaction.status !== 'empty' ? (
                <Button title="Take Reaction Test" variant="tinted" onPress={() => navigate('VigilanceTest')} />
              ) : null}
            </View>
          </WalkthroughReveal>
        </View>

        <WalkthroughReveal active={walkthrough.active} revealed={walkthrough.isRevealed('insights-reaction')} reduceMotion={walkthrough.reduceMotion}>
          {details}
        </WalkthroughReveal>
      </View>
    </AppScreen>
  );
}
