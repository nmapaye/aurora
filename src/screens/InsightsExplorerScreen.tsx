import React, { useState } from 'react';
import { Pressable, View } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import Svg, { Circle, Line, Path } from 'react-native-svg';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { SectionCard, SectionHeader } from '~/components/ui';
import { HealthRangeControl } from '~/components/health';
import { PlanningText as Text, timeText } from '~/features/planning/components';
import {
  bedtimePairs,
  checkInPairs,
  completeness,
  completedTests,
  dailyTimeline,
  inspectionPoints,
  vigilanceComparison,
  weekdayPatterns,
  weeklyReview,
  type InsightInput,
} from '~/features/insights/analysis';
import MetricExplanation from '~/features/insights/MetricExplanation';
import useNow from '~/hooks/useNow';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { goBack } from '~/navigation';
import { useStore } from '~/state/store';
import {
  addCalendarDays,
  localDateKey,
  startOfLocalDay,
} from '~/utils/calendar';

const dayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const value = (n: number | null, unit: string) =>
  n === null ? 'Unavailable' : `${n.toFixed(1)} ${unit}`;
const sections = [
  'Daily timeline',
  'Patterns',
  'Tests',
  'Completeness',
  'Weekly review',
] as const;
type Section = (typeof sections)[number];
function Scatter({
  points,
}: {
  points: ReturnType<typeof bedtimePairs>['points'];
}) {
  const palette = getAppPalette(useAppScheme()),
    maxX = Math.max(1, ...points.map((p) => p.caffeineMg)),
    maxY = Math.max(1, ...points.map((p) => p.sleepHours));
  return (
    <View
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <Svg width="100%" height={180} viewBox="0 0 320 180">
        <Line
          x1={20}
          x2={305}
          y1={160}
          y2={160}
          stroke={palette.textSecondary}
        />
        <Line x1={20} x2={20} y1={10} y2={160} stroke={palette.textSecondary} />
        {points.map((p, i) => (
          <Circle
            key={i}
            cx={20 + (p.caffeineMg / maxX) * 280}
            cy={160 - (p.sleepHours / maxY) * 145}
            r={5}
            fill={palette.tint}
          />
        ))}
      </Svg>
    </View>
  );
}
function Inspector({ input, date }: { input: InsightInput; date: string }) {
  const points = inspectionPoints(input, date),
    [cursor, setCursor] = useState(0),
    [table, setTable] = useState(false),
    [width, setWidth] = useState(300),
    palette = getAppPalette(useAppScheme());
  const index = Math.min(cursor, points.length - 1),
    point = points[index];
  if (!point) return null;
  const start = points[0].timestamp,
    span = points[points.length - 1].timestamp - start,
    max = Math.max(1, ...points.map((p) => p.caffeineMg));
  const path = (metric: 'caffeineMg' | 'alertness') =>
    points
      .map(
        (p, i) =>
          `${i ? 'L' : 'M'} ${10 + ((p.timestamp - start) / span) * 280} ${150 - (p[metric] / (metric === 'caffeineMg' ? max : 100)) * 140}`,
      )
      .join(' ');
  return (
    <SectionCard>
      <SectionHeader title="Inspect caffeine and alertness" />
      <Text>
        Solid line: caffeine, 0–{max.toFixed(0)} mg. Dashed line: model
        alertness, 0–100. Time runs left to right across the selected day.
      </Text>
      <Pressable
        testID="inspection-chart"
        accessible={false}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
        onLayout={(e) => setWidth(e.nativeEvent.layout.width)}
        onPress={(e) => {
          const target =
            start +
            Math.max(
              0,
              Math.min(
                1,
                ((e.nativeEvent.locationX / Math.max(1, width)) * 300 - 10) /
                  280,
              ),
            ) *
              span;
          setCursor(
            points.reduce(
              (best, p, i) =>
                Math.abs(p.timestamp - target) <
                Math.abs(points[best].timestamp - target)
                  ? i
                  : best,
              0,
            ),
          );
        }}
      >
        <Svg
          testID="inspection-svg"
          width="100%"
          height={160}
          viewBox="0 0 300 160"
          preserveAspectRatio="none"
        >
          <Path
            d={path('caffeineMg')}
            stroke={palette.textPrimary}
            fill="none"
            strokeWidth={3}
          />
          <Path
            d={path('alertness')}
            stroke={palette.tint}
            fill="none"
            strokeWidth={2}
            strokeDasharray="5 4"
          />
          <Line
            x1={10 + ((point.timestamp - start) / span) * 280}
            x2={10 + ((point.timestamp - start) / span) * 280}
            y1={5}
            y2={155}
            stroke={palette.textSecondary}
          />
        </Svg>
      </Pressable>
      <Text>
        {timeText(point.timestamp)}: {point.caffeineMg.toFixed(1)} mg modeled
        caffeine; {point.alertness.toFixed(0)} of 100 modeled alertness
        {point.timestamp > input.now ? ' (forecast)' : ''}.
      </Text>
      <Button
        title="Earlier inspection time"
        disabled={index === 0}
        onPress={() => setCursor(Math.max(0, index - 1))}
      />
      <Button
        title="Later inspection time"
        disabled={index === points.length - 1}
        onPress={() => setCursor(Math.min(points.length - 1, index + 1))}
      />
      <Text>
        Tap the chart or use the buttons to move through 15-minute points and
        exact dose events. Buttons expose the same values as the chart.
      </Text>
      {!point.hasCaffeineRecord ? (
        <Text>
          No caffeine intake recorded on this date before the inspected time.
          Earlier recorded doses may still contribute residual caffeine.
        </Text>
      ) : null}
      {!point.hasSleepRecord ? (
        <Text>
          No completed sleep record in the preceding 24 hours. Missing sleep can
          lower the model estimate.
        </Text>
      ) : null}
      <Button
        title={table ? 'Hide inspection table' : 'Show inspection table'}
        onPress={() => setTable(!table)}
      />
      {table
        ? points.map((p) => (
            <Text key={p.timestamp}>
              {timeText(p.timestamp)}: caffeine {p.caffeineMg.toFixed(1)} mg;
              alertness {p.alertness.toFixed(0)} of 100
            </Text>
          ))
        : null}
      <MetricExplanation metric="caffeine" />
      <MetricExplanation metric="alertness" />
    </SectionCard>
  );
}
export default function InsightsExplorerScreen() {
  const state = useStore(),
    now = useNow(),
    [section, setSection] = useState<Section>('Daily timeline'),
    [range, setRange] = useState('14'),
    [dayOffset, setDayOffset] = useState(0),
    [datePicker, setDatePicker] = useState(false),
    [explicitDate, setExplicitDate] = useState<number | null>(null),
    [testId, setTestId] = useState<string | null>(null),
    [plotTable, setPlotTable] = useState(false);
  const input: InsightInput = {
    doses: state.doses,
    zeroDays: state.caffeine.zeroDays,
    sleeps: state.sleeps,
    checkIns: state.planning.checkIns,
    tests: state.vigilanceSessions,
    prefs: state.prefs,
    now,
  };
  const day = explicitDate ?? addCalendarDays(startOfLocalDay(now), dayOffset),
    date = localDateKey(day),
    days = Number(range),
    daily = completeness(input, days),
    timeline = dailyTimeline(input, date),
    patterns = weekdayPatterns(input, days),
    bed = bedtimePairs(input, days),
    paired = checkInPairs(input, days),
    tests = completedTests(input.tests, now),
    selected = tests.find((t) => t.id === testId),
    comparison = selected ? vigilanceComparison(selected, tests, now) : null,
    review = weeklyReview(input);
  const shiftDay = (offset: number) => {
    if (explicitDate !== null)
      setExplicitDate(addCalendarDays(explicitDate, offset));
    else setDayOffset(dayOffset + offset);
  };
  return (
    <AppScreen
      title="Explore insights"
      subtitle="Personal records and model estimates. Sample data is excluded."
      trailing={<Button title="Back" onPress={goBack} />}
    >
      <View style={{ gap: 16 }}>
        <View style={{ gap: 8 }}>
          {sections.map((s) => (
            <Button
              key={s}
              title={s}
              variant={section === s ? 'primary' : 'tinted'}
              accessibilityValue={{ text: section === s ? 'Selected' : '' }}
              onPress={() => setSection(s)}
            />
          ))}
        </View>
        {section === 'Patterns' || section === 'Completeness' ? (
          <HealthRangeControl
            accessibilityLabel="Analysis range"
            value={range}
            onChange={setRange}
            options={[
              { value: '7', label: 'W' },
              { value: '14', label: '2W' },
              { value: '30', label: 'M' },
            ]}
          />
        ) : null}
        {section === 'Daily timeline' ? (
          <>
            <SectionCard>
              <SectionHeader title={date} />
              <Button title="Previous day" onPress={() => shiftDay(-1)} />
              <Button
                title="Next day"
                disabled={date >= localDateKey(now)}
                onPress={() => shiftDay(1)}
              />
              <Button
                title="Choose timeline date"
                onPress={() => setDatePicker(!datePicker)}
              />
              {datePicker ? (
                <DateTimePicker
                  accessibilityLabel="Timeline date"
                  value={new Date(day)}
                  mode="date"
                  maximumDate={new Date(now)}
                  onChange={(e, d) => {
                    setDatePicker(false);
                    if (e.type !== 'dismissed' && d)
                      setExplicitDate(startOfLocalDay(d.getTime()));
                  }}
                />
              ) : null}
              <Text>
                Sleep that crosses this date’s boundary is shown with its full
                interval. Episodes combine recorded segments; gaps are not
                counted as sleep.
              </Text>
              {timeline.length ? (
                timeline.map((e) => (
                  <View
                    key={`${e.kind}:${e.id}`}
                    style={{ gap: 4, paddingVertical: 8 }}
                  >
                    <Text>
                      {timeText(e.timestamp)}
                      {e.end ? ` to ${timeText(e.end)}` : ''}
                    </Text>
                    <Text>
                      {e.label}. {e.detail}
                    </Text>
                  </View>
                ))
              ) : (
                <Text>
                  No personal events recorded for this day. This does not
                  confirm zero intake or no sleep.
                </Text>
              )}
              <MetricExplanation metric="sleep" />
            </SectionCard>
            <Inspector key={date} input={input} date={date} />
          </>
        ) : null}
        {section === 'Patterns' ? (
          <>
            <SectionCard>
              <SectionHeader title="Weekday comparison" />
              {patterns.map((p) => (
                <View key={p.weekday} style={{ paddingVertical: 8, gap: 4 }}>
                  <Text>{dayNames[p.weekday]}</Text>
                  <Text>
                    Caffeine {value(p.caffeineMean, 'mg')} ({p.caffeineCount}{' '}
                    recorded days); sleep {value(p.sleepMean, 'h')} (
                    {p.sleepCount} recorded days).
                  </Text>
                </View>
              ))}
              <MetricExplanation metric="weekday" />
            </SectionCard>
            <SectionCard>
              <SectionHeader title="Caffeine at sleep onset versus sleep duration" />
              <Text>
                {bed.points.length} paired main-sleep observations. Horizontal
                axis: modeled caffeine, 0–
                {Math.max(1, ...bed.points.map((p) => p.caffeineMg)).toFixed(
                  0,
                )}{' '}
                mg. Vertical axis: recorded sleep, 0–
                {Math.max(1, ...bed.points.map((p) => p.sleepHours)).toFixed(
                  1,
                )}{' '}
                h.
              </Text>
              <Scatter points={bed.points} />
              {bed.summary ? (
                <Text>
                  Recorded pair averages:{' '}
                  {bed.summary.meanCaffeineMg.toFixed(1)} mg at onset and{' '}
                  {bed.summary.meanSleepHours.toFixed(1)} h sleep across{' '}
                  {bed.summary.count} observations. This does not establish a
                  caffeine effect.
                </Text>
              ) : (
                <Text>
                  At least 5 paired sleep observations are needed for a
                  descriptive average. Missing intake coverage does not become a
                  zero-caffeine point.
                </Text>
              )}
              <Button
                title={
                  plotTable
                    ? 'Hide sleep-onset table'
                    : 'Show sleep-onset table'
                }
                onPress={() => setPlotTable(!plotTable)}
              />
              {plotTable
                ? bed.points.map((p) => (
                    <Text key={p.sleepStart}>
                      {timeText(p.sleepStart)}: {p.caffeineMg.toFixed(1)} mg;
                      sleep until {timeText(p.wakeTime)},{' '}
                      {p.sleepHours.toFixed(1)} h
                    </Text>
                  ))
                : null}
              <MetricExplanation metric="bedtime" />
            </SectionCard>
            <SectionCard>
              <SectionHeader title="Subjective alertness and reaction tests" />
              <Text>
                {paired.pairs.length} check-ins paired within 30 minutes. A test
                may be paired more than once. Subjective rating and reaction
                time use separate scales.
              </Text>
              {paired.summary ? (
                <Text>
                  {paired.summary.count} pairs: subjective mean{' '}
                  {paired.summary.meanRating.toFixed(1)} of 5; reaction-time
                  median {paired.summary.medianReactionMs.toFixed(0)} ms.
                  Descriptive observations only.
                </Text>
              ) : (
                <Text>
                  At least 5 pairs with reaction medians are needed for a
                  summary.
                </Text>
              )}
              {paired.pairs.map((p) => (
                <Text key={p.checkIn.id}>
                  {timeText(p.checkIn.timestamp)}: subjective {p.checkIn.rating}{' '}
                  of 5. Test {timeText(p.test.completedAt)}: reaction median{' '}
                  {value(p.test.medianReactionMs, 'ms')}, score {p.test.score}{' '}
                  of 100.
                </Text>
              ))}
              <MetricExplanation metric="pairing" />
            </SectionCard>
          </>
        ) : null}
        {section === 'Tests' ? (
          <>
            <SectionCard>
              <SectionHeader title="Vigilance history" />
              <Text>
                {tests.length} completed personal tests. Select a test for its
                recorded metrics and prior baseline.
              </Text>
              {tests.length ? (
                tests.map((t) => (
                  <Button
                    key={t.id}
                    title={`${timeText(t.completedAt)} · ${t.score} of 100`}
                    accessibilityLabel={`Inspect test ${timeText(t.completedAt)} ${t.id}`}
                    onPress={() => setTestId(t.id)}
                  />
                ))
              ) : (
                <Text>No completed personal tests.</Text>
              )}
            </SectionCard>
            {selected && comparison ? (
              <SectionCard>
                <SectionHeader title="Test details" />
                <Text>
                  {timeText(selected.startedAt)} to{' '}
                  {timeText(selected.completedAt)};{' '}
                  {(selected.durationMs / 1000).toFixed(0)} seconds.
                </Text>
                <Text>
                  Median {value(selected.medianReactionMs, 'ms')}; mean{' '}
                  {value(selected.meanReactionMs, 'ms')}; fastest{' '}
                  {value(selected.fastestReactionMs, 'ms')}; reaction variation{' '}
                  {value(selected.reactionStdDevMs, 'ms')}.
                </Text>
                <Text>
                  {selected.trialCount} trials; {selected.validReactionCount}{' '}
                  valid reactions; {selected.lapseCount} lapses;{' '}
                  {selected.falseStartCount} false starts.
                </Text>
                <Text>
                  Test score {selected.score} of 100, {selected.rating}.
                </Text>
                <Text>
                  {comparison.count} earlier eligible tests.{' '}
                  {comparison.medianMs === null
                    ? 'At least 3 earlier tests and a valid selected reaction median are required.'
                    : `Prior median ${comparison.medianMs.toFixed(0)} ms; selected difference ${comparison.changeMs! >= 0 ? '+' : ''}${comparison.changeMs!.toFixed(0)} ms. Negative means faster.`}
                </Text>
                <MetricExplanation metric="baseline" />
              </SectionCard>
            ) : null}
            <MetricExplanation metric="vigilance" />
          </>
        ) : null}
        {section === 'Completeness' ? (
          <SectionCard>
            <SectionHeader title="Recorded data by day" />
            <Text>
              Today is still in progress. A record flag does not guarantee
              complete coverage.
            </Text>
            {daily.map((d) => (
              <View key={d.date} style={{ paddingVertical: 8, gap: 4 }}>
                <Text>{d.date}</Text>
                <Text>
                  {d.caffeineState === 'missing'
                    ? 'Caffeine missing'
                    : d.caffeineState === 'zero'
                      ? 'Confirmed caffeine-free (0 mg)'
                      : `Caffeine recorded (${d.caffeineMg!.toFixed(0)} mg)`}
                  ;{' '}
                  {d.sleepHours === null
                    ? 'sleep missing'
                    : `sleep recorded (${d.sleepHours.toFixed(1)} h)`}
                  ; {d.testCount} tests; {d.checkInCount} check-ins.
                </Text>
              </View>
            ))}
            <MetricExplanation metric="completeness" />
          </SectionCard>
        ) : null}
        {section === 'Weekly review' ? (
          <SectionCard>
            <SectionHeader title={`${review.start} to ${review.end}`} />
            <Text>
              Last 7 calendar days, including today so far, compared with the
              preceding 7 days. Generated on this device from personal records.
            </Text>
            <Text>
              {review.current.missingCaffeineDays} of 7 days missing caffeine;{' '}
              {review.current.missingSleepDays} of 7 days missing sleep.
              Coverage can explain apparent changes.
            </Text>
            <Text>
              Caffeine daily mean {value(review.current.caffeineMeanMg, 'mg')}{' '}
              from {review.current.caffeineCount} recorded days; prior mean{' '}
              {value(review.previous.caffeineMeanMg, 'mg')} from{' '}
              {review.previous.caffeineCount} days. Change{' '}
              {value(review.caffeineChangeMg, 'mg')}.
            </Text>
            <Text>
              Sleep daily mean {value(review.current.sleepMeanHours, 'h')} from{' '}
              {review.current.sleepCount} recorded days; prior mean{' '}
              {value(review.previous.sleepMeanHours, 'h')} from{' '}
              {review.previous.sleepCount} days. Change{' '}
              {value(review.sleepChangeHours, 'h')}.
            </Text>
            <Text>
              Your caffeine target: {review.targets.dailyCaffeineMg} mg/day.{' '}
              {review.current.caffeineWithinTarget} of{' '}
              {review.current.caffeineCount} recorded days at or below it. Your
              sleep target: {review.targets.sleepHours} h/day.{' '}
              {review.current.sleepAtTarget} of {review.current.sleepCount}{' '}
              recorded sleep days reached it.
            </Text>
            <Text>
              {review.current.testCount} completed tests and{' '}
              {review.current.checkInCount} check-ins this week;{' '}
              {review.previous.testCount} tests and{' '}
              {review.previous.checkInCount} check-ins in the preceding week.
            </Text>
            <MetricExplanation metric="weekly" />
          </SectionCard>
        ) : null}
      </View>
    </AppScreen>
  );
}
