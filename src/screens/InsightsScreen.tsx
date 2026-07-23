import { RouteProp, useRoute } from '@react-navigation/native';
import React, { useEffect, useMemo, useState } from 'react';
import { Share, Text, View } from 'react-native';
import Svg, {
  Defs,
  Line as SvgLine,
  LinearGradient,
  Path,
  Stop,
} from 'react-native-svg';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import CaffeineTodayGraph from '~/components/CaffeineTodayGraph';
import HistoryContent from '~/components/HistoryContent';
import useAppScheme from '~/hooks/useAppScheme';
import {
  ListRow,
  SectionCard,
  SectionHeader,
  SegmentedControl,
  StatTile,
} from '~/components/ui';
import useSleepGuidance from '~/hooks/useSleepGuidance';
import { navigate } from '~/navigation';
import type { RootTabParamList } from '~/navigation/types';
import { makeDailyTotalsCSV, makeSummaryText } from '~/services/storage/export';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { radii, spacing, typeRamp } from '~/theme/tokens';

type RangeKey = '7' | '14' | '30';
type InsightsSection = 'summary' | 'trends' | 'history';

function TrendChart({
  data,
  height = 160,
}: {
  data: number[];
  height?: number;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const [width, setWidth] = useState(0);
  const padding = { top: 12, right: 8, bottom: 18, left: 8 };
  const chartWidth = Math.max(0, width - padding.left - padding.right);
  const chartHeight = Math.max(0, height - padding.top - padding.bottom);
  const min = Math.min(...data, 0);
  const max = Math.max(...data, 1);
  const pad = (max - min) * 0.1;
  const yMin = min - pad;
  const yMax = max + pad;
  const toX = (index: number) =>
    data.length <= 1 ? 0 : (index / (data.length - 1)) * chartWidth;
  const toY = (value: number) =>
    chartHeight - ((value - yMin) / Math.max(1e-6, yMax - yMin)) * chartHeight;

  let linePath = '';
  data.forEach((value, index) => {
    const x = padding.left + toX(index);
    const y = padding.top + toY(value);
    linePath += index === 0 ? `M ${x} ${y}` : ` L ${x} ${y}`;
  });

  let areaPath = '';
  if (data.length > 0) {
    const x0 = padding.left + toX(0);
    const xN = padding.left + toX(data.length - 1);
    const y0 = padding.top + toY(data[0]);
    const yBase = padding.top + toY(yMin);
    areaPath = `M ${x0} ${y0}`;
    for (let index = 1; index < data.length; index += 1) {
      areaPath += ` L ${padding.left + toX(index)} ${padding.top + toY(data[index])}`;
    }
    areaPath += ` L ${xN} ${yBase} L ${x0} ${yBase} Z`;
  }

  return (
    <View
      onLayout={(event) => setWidth(event.nativeEvent.layout.width)}
      style={{ width: '100%', height }}
    >
      {width > 0 ? (
        <Svg width={width} height={height}>
          {Array.from({ length: 3 }).map((_, index) => {
            const y = padding.top + (index / 2) * chartHeight;
            return (
              <SvgLine
                key={`h-${index}`}
                x1={padding.left}
                y1={y}
                x2={width - padding.right}
                y2={y}
                stroke={palette.separator}
                strokeWidth={1}
                strokeDasharray={[2, 6]}
              />
            );
          })}
          <Defs>
            <LinearGradient id="trendArea" x1="0" y1="0" x2="0" y2="1">
              <Stop offset={0} stopColor={palette.tint} stopOpacity={0.22} />
              <Stop offset={1} stopColor={palette.tint} stopOpacity={0.04} />
            </LinearGradient>
          </Defs>
          {areaPath ? <Path d={areaPath} fill="url(#trendArea)" /> : null}
          {linePath ? (
            <Path
              d={linePath}
              stroke={palette.tint}
              strokeWidth={3}
              fill="none"
              strokeLinejoin="round"
              strokeLinecap="round"
            />
          ) : null}
        </Svg>
      ) : null}
    </View>
  );
}

function fmtDay(timestamp: number) {
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
    }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toDateString();
  }
}

function fmtDateTime(timestamp: number) {
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toLocaleString();
  }
}

function fmtClock(timestamp: number) {
  try {
    return new Intl.DateTimeFormat(undefined, {
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toLocaleTimeString();
  }
}

export default function InsightsScreen() {
  const route = useRoute<RouteProp<RootTabParamList, 'Insights'>>();
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const doses = useStore((state) => state.doses);
  const vigilanceSessions = useStore((state) => state.vigilanceSessions);
  const dailyLimit = useStore((state) => state.prefs.dailyLimitMg ?? 400);
  const demoMode = useStore((state) => state.demoMode);
  const sleepGuidance = useSleepGuidance();

  const [section, setSection] = useState<InsightsSection>(
    route.params?.section ?? 'summary',
  );
  const [range, setRange] = useState<RangeKey>('14');

  useEffect(() => {
    if (route.params?.section) {
      setSection(route.params.section);
    }
  }, [route.params?.section]);

  const daysInRange = range === '7' ? 7 : range === '14' ? 14 : 30;

  const { days, totals, previousTotals } = useMemo(() => {
    const endOfDay = (date: Date) =>
      new Date(
        date.getFullYear(),
        date.getMonth(),
        date.getDate(),
        23,
        59,
        59,
        999,
      ).getTime();
    const startOfDay = (date: Date) =>
      new Date(
        date.getFullYear(),
        date.getMonth(),
        date.getDate(),
        0,
        0,
        0,
        0,
      ).getTime();

    const buildWindow = (startMs: number) => {
      const dayStarts: number[] = [];
      const dailyTotals: number[] = [];
      const start = startOfDay(new Date(startMs));
      for (let index = 0; index < daysInRange; index += 1) {
        const current = new Date(start);
        current.setDate(current.getDate() + index);
        const dayStart = startOfDay(current);
        const dayEnd = endOfDay(current);
        dayStarts.push(dayStart);
        dailyTotals.push(
          doses.reduce(
            (sum, dose) =>
              dose.timestamp >= dayStart && dose.timestamp <= dayEnd
                ? sum + dose.mg
                : sum,
            0,
          ),
        );
      }
      return { dayStarts, dailyTotals };
    };

    const today = new Date();
    const end = endOfDay(today);
    const start = new Date(end);
    start.setDate(start.getDate() - (daysInRange - 1));
    const current = buildWindow(start.getTime());

    const previousEnd = startOfDay(new Date(start.getTime() - 1));
    const previousStart = new Date(previousEnd);
    previousStart.setDate(previousStart.getDate() - (daysInRange - 1));
    const previous = buildWindow(previousStart.getTime());

    return {
      days: current.dayStarts,
      totals: current.dailyTotals,
      previousTotals: previous.dailyTotals,
    };
  }, [daysInRange, doses]);

  const weeklyAverage = Math.round(
    totals.reduce((sum, value) => sum + value, 0) / Math.max(1, totals.length),
  );
  const previousAverage = Math.round(
    previousTotals.reduce((sum, value) => sum + value, 0) /
      Math.max(1, previousTotals.length),
  );
  const deltaPct =
    previousAverage > 0
      ? Math.round((weeklyAverage / previousAverage - 1) * 100)
      : undefined;

  const adherence = useMemo(() => {
    const daysWithData = totals.filter((value) => value > 0).length;
    const withinLimit = totals.filter(
      (value) => value > 0 && value <= dailyLimit,
    ).length;
    let streak = 0;
    for (let index = totals.length - 1; index >= 0; index -= 1) {
      const value = totals[index];
      if (value > 0 && value <= dailyLimit) {
        streak += 1;
      } else if (value > 0) {
        streak = 0;
        break;
      }
    }
    return {
      pct:
        daysWithData > 0 ? Math.round((withinLimit / daysWithData) * 100) : 0,
      streak,
    };
  }, [dailyLimit, totals]);

  const daypart = useMemo(() => {
    const bins = [0, 0, 0, 0];
    const start = days[0] ?? Date.now();
    const end = (days[days.length - 1] ?? Date.now()) + 86_400_000;
    for (const dose of doses) {
      if (dose.timestamp < start || dose.timestamp > end) continue;
      const hour = new Date(dose.timestamp).getHours();
      const index =
        hour >= 5 && hour < 11
          ? 0
          : hour >= 11 && hour < 17
            ? 1
            : hour >= 17 && hour < 21
              ? 2
              : 3;
      bins[index] += dose.mg;
    }
    return bins;
  }, [days, doses]);

  const sourceMix = useMemo(() => {
    const start = days[0] ?? Date.now();
    const end = (days[days.length - 1] ?? Date.now()) + 86_400_000;
    const totalsBySource = new Map<string, number>();
    const normalizeSource = (source?: string) => {
      if (!source) return 'Other';
      const value = source.toLowerCase();
      if (
        value.includes('espresso') ||
        value.includes('drip') ||
        value.includes('brew')
      )
        return 'Coffee';
      if (value.includes('tea') || value.includes('matcha')) return 'Tea';
      if (value.includes('energy')) return 'Energy';
      if (value.includes('pill')) return 'Pills';
      return 'Other';
    };

    for (const dose of doses) {
      if (dose.timestamp < start || dose.timestamp > end) continue;
      const key = normalizeSource(dose.source);
      totalsBySource.set(key, (totalsBySource.get(key) || 0) + dose.mg);
    }

    const entries = Array.from(totalsBySource.entries()).sort(
      (a, b) => b[1] - a[1],
    );
    const totalMg = entries.reduce((sum, entry) => sum + entry[1], 0) || 1;
    return entries.map(([label, mg]) => ({
      label,
      mg,
      pct: Math.round((mg / totalMg) * 100),
    }));
  }, [days, doses]);

  const vigilanceSummary = useMemo(() => {
    const latest = vigilanceSessions[0];
    const weekCutoff = Date.now() - (7 * 24 * 86_400_000) / 24;
    const recent = vigilanceSessions.filter(
      (session) => session.completedAt >= weekCutoff,
    );
    const averageScore =
      recent.length > 0
        ? Math.round(
            recent.reduce((sum, session) => sum + session.score, 0) /
              recent.length,
          )
        : undefined;
    const trendSessions = [...vigilanceSessions]
      .slice(0, 7)
      .sort((a, b) => a.completedAt - b.completedAt);
    return {
      latest,
      averageScore,
      trendSessions,
      hasBaseline: vigilanceSessions.length >= 3,
    };
  }, [vigilanceSessions]);

  const shareMonthlySummary = async () => {
    const monthStart = Date.now() - 30 * 86_400_000;
    const monthDoses = doses.filter((dose) => dose.timestamp >= monthStart);
    const totalMg = monthDoses.reduce((sum, dose) => sum + dose.mg, 0);
    const daypartRows = [
      { label: 'Morning', mg: daypart[0] },
      { label: 'Midday', mg: daypart[1] },
      { label: 'Evening', mg: daypart[2] },
      { label: 'Late', mg: daypart[3] },
    ];
    await Share.share({
      message: makeSummaryText({
        range: 'Last 30 Days',
        totalMg,
        avgMg: Math.round(totalMg / 30),
        adherencePct: adherence.pct,
        streakDays: adherence.streak,
        dayparts: daypartRows,
        sources: sourceMix.map((item) => ({
          label: item.label,
          mg: item.mg,
          pct: item.pct,
        })),
      }),
    });
  };

  const shareDailyTotalsCSV = async () => {
    await Share.share({
      message: makeDailyTotalsCSV(
        days.map((day, index) => ({
          date: new Date(day).toISOString().slice(0, 10),
          mg: totals[index] ?? 0,
        })),
      ),
    });
  };

  return (
    <AppScreen
      title="Insights"
      subtitle="Caffeine, sleep, and alertness trends."
    >
      <View style={{ gap: spacing.md }}>
        <SegmentedControl
          value={section}
          onChange={setSection}
          options={[
            { key: 'summary', label: 'Summary' },
            { key: 'trends', label: 'Trends' },
            { key: 'history', label: 'History' },
          ]}
        />

        {section === 'summary' ? (
          <>
            <SectionHeader
              prominence="prominent"
              title="Summary"
              actionLabel="Share"
              onAction={shareMonthlySummary}
            />
            <View style={{ flexDirection: 'row', gap: spacing.sm }}>
              <StatTile
                label={`${daysInRange}-day average`}
                value={`${weeklyAverage} mg`}
                detail={
                  typeof deltaPct === 'number'
                    ? `${deltaPct >= 0 ? 'Up' : 'Down'} ${Math.abs(deltaPct)}% vs prior window`
                    : 'Building baseline'
                }
              />
              <StatTile
                label="Limit adherence"
                value={`${adherence.pct}%`}
                detail={`Current streak ${adherence.streak} day${adherence.streak === 1 ? '' : 's'}`}
              />
            </View>

            <SectionCard>
              {demoMode ? (
                <InlineDemoNotice paletteColor={palette.textTertiary} />
              ) : null}
              <SectionHeader title="Today" />
              <CaffeineTodayGraph />
              <Text
                style={{
                  ...typeRamp.footnote,
                  color: palette.textTertiary,
                }}
              >
                Today’s curve is separate from longer-range trends.
              </Text>
            </SectionCard>

            <SectionCard>
              <SectionHeader
                title="Vigilance"
                action={
                  <Button
                    title={vigilanceSummary.latest ? 'Run Again' : 'Start Test'}
                    variant="plain"
                    onPress={() => navigate('VigilanceTest')}
                  />
                }
              />
              {vigilanceSummary.latest ? (
                <>
                  <View style={{ flexDirection: 'row', gap: spacing.sm }}>
                    <StatTile
                      label="Latest"
                      value={`${vigilanceSummary.latest.score}`}
                      detail={`${vigilanceSummary.latest.rating} • ${fmtDateTime(vigilanceSummary.latest.completedAt)}`}
                    />
                    <StatTile
                      label="7-day average"
                      value={
                        typeof vigilanceSummary.averageScore === 'number'
                          ? `${vigilanceSummary.averageScore}`
                          : '—'
                      }
                      detail={`${vigilanceSummary.trendSessions.length} recent sessions`}
                    />
                  </View>
                  <ListRow
                    title="Median reaction"
                    subtitle="Latest completed session"
                    value={`${vigilanceSummary.latest.medianReactionMs ?? '—'} ms`}
                  />
                  <ListRow
                    title="Accuracy markers"
                    subtitle="Lapses and false starts"
                    value={`${vigilanceSummary.latest.lapseCount} / ${vigilanceSummary.latest.falseStartCount}`}
                  />
                  {vigilanceSummary.hasBaseline ? (
                    <TrendChart
                      data={vigilanceSummary.trendSessions.map(
                        (session) => session.score,
                      )}
                      height={132}
                    />
                  ) : (
                    <Text
                      style={{
                        ...typeRamp.footnote,
                        color: palette.textTertiary,
                      }}
                    >
                      Complete at least three sessions to build a usable
                      attentiveness baseline.
                    </Text>
                  )}
                </>
              ) : (
                <Text
                  style={{
                    ...typeRamp.subheadline,
                    color: palette.textSecondary,
                  }}
                >
                  No vigilance sessions yet.
                </Text>
              )}
            </SectionCard>

            <SectionCard>
              <SectionHeader
                title="Share and Export"
                action={
                  <Button
                    title="Export CSV"
                    variant="plain"
                    onPress={shareDailyTotalsCSV}
                  />
                }
              />
              <ListRow
                title="Daily caffeine totals"
                subtitle="Share the selected window as CSV."
                value={`${daysInRange} days`}
              />
            </SectionCard>

            <SectionCard>
              <SectionHeader prominence="prominent" title="Guidance" />
              <ListRow
                title="Suggested bedtime"
                subtitle={`Projected active caffeine ${sleepGuidance.mgAtBed} mg`}
                value={fmtClock(sleepGuidance.bedtime)}
              />
              <ListRow
                title="Suggested wake"
                subtitle="90-minute sleep cycles, aiming for a normal morning window"
                value={fmtClock(sleepGuidance.wake)}
              />
            </SectionCard>
          </>
        ) : null}

        {section === 'trends' ? (
          <>
            <SectionHeader prominence="prominent" title="Trends" />
            <SectionCard>
              <SegmentedControl
                value={range}
                onChange={setRange}
                options={[
                  { key: '7', label: '7d' },
                  { key: '14', label: '14d' },
                  { key: '30', label: '30d' },
                ]}
              />
              <Text
                style={{
                  ...typeRamp.footnote,
                  color: palette.textTertiary,
                }}
              >
                Compare a short recent window without filters.
              </Text>
            </SectionCard>

            <SectionCard>
              <SectionHeader
                prominence="prominent"
                title={`${daysInRange}-day caffeine trend`}
              />
              <ListRow
                title="Latest day"
                subtitle={`${fmtDay(days[days.length - 1] ?? Date.now())}`}
                value={`${totals[totals.length - 1] ?? 0} mg`}
              />
              <TrendChart data={totals} />
              <View style={{ flexDirection: 'row' }}>
                <Text
                  style={{
                    flex: 1,
                    ...typeRamp.footnote,
                    color: palette.textSecondary,
                  }}
                >
                  {fmtDay(days[0] ?? Date.now())}
                </Text>
                <Text
                  style={{
                    flex: 1,
                    textAlign: 'right',
                    ...typeRamp.footnote,
                    color: palette.textSecondary,
                  }}
                >
                  {fmtDay(days[days.length - 1] ?? Date.now())}
                </Text>
              </View>
            </SectionCard>

            <SectionCard>
              <SectionHeader prominence="prominent" title="Daypart Mix" />
              {[
                ['05–11', daypart[0]],
                ['11–17', daypart[1]],
                ['17–21', daypart[2]],
                ['21–05', daypart[3]],
              ].map(([label, mg]) => (
                <View key={String(label)} style={{ gap: spacing.xs }}>
                  <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                    <Text
                      style={{
                        flex: 1,
                        ...typeRamp.subheadline,
                        color: palette.textSecondary,
                      }}
                    >
                      {label}
                    </Text>
                    <Text
                      style={{
                        ...typeRamp.subheadline,
                        color: palette.textPrimary,
                      }}
                    >
                      {Math.round(Number(mg))} mg
                    </Text>
                  </View>
                  <View
                    style={{
                      height: 10,
                      borderRadius: radii.capsule,
                      backgroundColor: palette.cardMuted,
                      overflow: 'hidden',
                    }}
                  >
                    <View
                      style={{
                        width: `${Math.min(
                          100,
                          Number(mg) === 0
                            ? 0
                            : (Number(mg) / Math.max(1, Math.max(...daypart))) *
                                100,
                        )}%`,
                        height: '100%',
                        backgroundColor: palette.tint,
                      }}
                    />
                  </View>
                </View>
              ))}
            </SectionCard>

            <SectionCard>
              <SectionHeader prominence="prominent" title="Source Mix" />
              {sourceMix.length === 0 ? (
                <Text
                  style={{
                    ...typeRamp.subheadline,
                    color: palette.textSecondary,
                  }}
                >
                  No logged sources in this window yet.
                </Text>
              ) : (
                sourceMix.map((item) => (
                  <ListRow
                    key={item.label}
                    title={item.label}
                    subtitle={`${item.pct}% of intake`}
                    value={`${item.mg} mg`}
                  />
                ))
              )}
            </SectionCard>
          </>
        ) : null}

        {section === 'history' ? <HistoryContent /> : null}
      </View>
    </AppScreen>
  );
}

function InlineDemoNotice({ paletteColor }: { paletteColor: string }) {
  return (
    <Text
      style={{
        ...typeRamp.footnote,
        color: paletteColor,
      }}
    >
      Sample data is active. Shared summaries include example records.
    </Text>
  );
}
