import React, { useMemo, useRef, useState } from 'react';
import type { AccessibilityActionEvent } from 'react-native';
import {
  PanResponder,
  Pressable,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import Svg, {
  Circle,
  Defs,
  Line,
  LinearGradient,
  Path,
  Stop,
} from 'react-native-svg';

import {
  describeCaffeineDay,
  describeInspection,
  formatClockTime,
  inspectCaffeinePoint,
  nearestIndex,
  nowIndex,
} from '~/features/summary/presentation';
import useAppScheme from '~/hooks/useAppScheme';
import useLargeText from '~/hooks/useLargeText';
import { useTodayCaffeineSeries } from '~/hooks/useTodayCaffeineSeries';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import {
  controlSizes,
  fontScaling,
  motion,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';

const STEP_MINUTES = 15;
const HOUR_MS = 3_600_000;
const AXIS_WIDTH = 40;
const PLOT_PADDING = { top: 12, right: 8, bottom: 8 };
const DOSE_RADIUS = 4;
// Movement within this distance is still a tap; past it the gesture commits
// to one axis for its lifetime.
const TOUCH_SLOP = 6;
const AXIS_MAX_FONT_SCALE = 1.2;
const AXIS_LINE_RATIO = 1.4;

type GestureAxis = 'undecided' | 'horizontal' | 'vertical';

function fmtHour(ts: number) {
  try {
    return new Intl.DateTimeFormat(undefined, { hour: 'numeric' }).format(
      new Date(ts),
    );
  } catch {
    return new Date(ts).getHours().toString();
  }
}

// A clean upper bound so the axis reads 0 / half / max in round numbers.
function niceMax(value: number) {
  const target = Math.max(50, value * 1.1);
  const step = target > 200 ? 100 : 50;
  return Math.ceil(target / step) * step;
}

function pathThrough(points: { x: number; y: number }[]) {
  return points
    .map((pt, i) => `${i === 0 ? 'M' : 'L'} ${pt.x} ${pt.y}`)
    .join(' ');
}

// Today's active caffeine: the half-life model as a line (solid until now,
// dashed as a projection), logged doses as dots on the baseline. Tap or drag
// to inspect a time; VoiceOver users adjust the same selection in hour steps.
export default function CaffeineTodayGraph({
  height = 200,
  showCaption = true,
  inspectable = true,
}: {
  height?: number;
  showCaption?: boolean;
  inspectable?: boolean;
}) {
  const palette = getAppPalette(useAppScheme());
  const largeText = useLargeText();
  const { fontScale } = useWindowDimensions();
  // Axis labels scale a little; their row grows with them so none clip.
  const axisLabelHeight = Math.ceil(
    typeRamp.caption.fontSize *
      AXIS_LINE_RATIO *
      Math.min(fontScale, AXIS_MAX_FONT_SCALE),
  );
  const { series, start, end, now } = useTodayCaffeineSeries(STEP_MINUTES);
  const doses = useStore((s) => s.doses);
  const sleeps = useStore((s) => s.sleeps);
  const prefs = useStore((s) => s.prefs);
  const [width, setWidth] = useState(0);
  // The selection is a time, not an index, so it stays put when the shared
  // clock moves the "now" point within the series.
  const [selectedT, setSelectedT] = useState<number | null>(null);
  const accent = palette.caffeineAccent;
  const domain = Math.max(1, end - start);

  const chart = useMemo(() => {
    const plot = {
      x: AXIS_WIDTH,
      y: PLOT_PADDING.top,
      width: Math.max(0, width - AXIS_WIDTH - PLOT_PADDING.right),
      height: Math.max(0, height - PLOT_PADDING.top - PLOT_PADDING.bottom),
    };
    const yMax = niceMax(Math.max(0, ...series.map((p) => p.mg)));
    const xFor = (t: number) =>
      plot.x +
      Math.min(plot.width, Math.max(0, ((t - start) / domain) * plot.width));
    const yFor = (mg: number) =>
      plot.y + plot.height - (Math.max(0, mg) / yMax) * plot.height;
    const points = series.map((p) => ({ x: xFor(p.t), y: yFor(p.mg) }));
    const split = nowIndex(series, now);
    const past = points.slice(0, split + 1);
    const future = points.slice(split);
    const baseY = plot.y + plot.height;
    const areaPath =
      past.length > 1
        ? `${pathThrough(past)} L ${past[past.length - 1].x} ${baseY} L ${past[0].x} ${baseY} Z`
        : '';
    const yTicks = [0, yMax / 2, yMax].map((value) => ({
      value,
      y: yFor(value),
    }));
    const hourTicks = [0, 6, 12, 18].map((hour) => {
      const d = new Date(start);
      d.setHours(hour, 0, 0, 0);
      return { t: d.getTime(), x: xFor(d.getTime()) };
    });
    const doseMarks = doses
      .filter((dose) => dose.timestamp >= start && dose.timestamp < end)
      .map((dose) => ({
        key: `${dose.timestamp}-${dose.mg}`,
        x: xFor(dose.timestamp),
      }));
    return {
      plot,
      baseY,
      points,
      xs: points.map((pt) => pt.x),
      pastPath: past.length > 1 ? pathThrough(past) : '',
      futurePath: future.length > 1 ? pathThrough(future) : '',
      areaPath,
      nowX: xFor(now),
      yTicks,
      hourTicks,
      doseMarks,
    };
  }, [domain, doses, end, height, now, series, start, width]);

  const seriesTimes = useMemo(() => series.map((p) => p.t), [series]);
  const selectedIndex =
    selectedT !== null && selectedT >= start && selectedT <= end
      ? nearestIndex(seriesTimes, selectedT)
      : null;
  const activeIndex =
    selectedIndex !== null && selectedIndex >= 0
      ? selectedIndex
      : nowIndex(series, now);
  const activePoint = series[activeIndex];
  const inspection = activePoint
    ? inspectCaffeinePoint({
        point: activePoint,
        doses,
        sleeps,
        prefs,
        dayStart: start,
        now,
      })
    : null;
  const selectedPoint =
    selectedIndex !== null ? chart.points[activeIndex] : undefined;

  const daySummary = useMemo(
    () => describeCaffeineDay({ series, doses, dayStart: start, dayEnd: end }),
    [doses, end, series, start],
  );

  // The responder is created once; refs keep it reading the latest geometry.
  const xsRef = useRef(chart.xs);
  xsRef.current = chart.xs;
  const seriesRef = useRef(series);
  seriesRef.current = series;
  const inspectableRef = useRef(inspectable);
  inspectableRef.current = inspectable;
  const gesture = useRef<{ grantX: number; axis: GestureAxis }>({
    grantX: 0,
    axis: 'undecided',
  });
  const selectAt = (x: number) => {
    const index = nearestIndex(xsRef.current, x);
    const point = seriesRef.current[index];
    if (point) setSelectedT(point.t);
  };
  const selectAtRef = useRef(selectAt);
  selectAtRef.current = selectAt;

  // The chart sits inside the page's vertical ScrollView. It becomes the
  // responder on touch start only so a tap can select; until a gesture
  // commits to the horizontal axis it yields to the ScrollView and never
  // blocks native scrolling. Once a gesture commits to an axis it keeps it: a
  // vertical swipe that later drifts sideways stays a scroll.
  const responder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => inspectableRef.current,
        onMoveShouldSetPanResponder: (_event, g) =>
          inspectableRef.current &&
          Math.abs(g.dx) > TOUCH_SLOP &&
          Math.abs(g.dx) > Math.abs(g.dy),
        onShouldBlockNativeResponder: () => false,
        onPanResponderGrant: (event) => {
          gesture.current = {
            grantX: event.nativeEvent.locationX,
            axis: 'undecided',
          };
        },
        onPanResponderMove: (_event, g) => {
          const state = gesture.current;
          if (
            state.axis === 'undecided' &&
            Math.max(Math.abs(g.dx), Math.abs(g.dy)) > TOUCH_SLOP
          ) {
            state.axis =
              Math.abs(g.dx) > Math.abs(g.dy) ? 'horizontal' : 'vertical';
          }
          if (state.axis === 'horizontal') {
            selectAtRef.current(state.grantX + g.dx);
          }
        },
        onPanResponderTerminationRequest: () =>
          gesture.current.axis !== 'horizontal',
        onPanResponderRelease: () => {
          if (gesture.current.axis === 'undecided') {
            selectAtRef.current(gesture.current.grantX);
          }
          gesture.current.axis = 'undecided';
        },
        onPanResponderTerminate: () => {
          gesture.current.axis = 'undecided';
        },
      }),
    [],
  );

  const stepByHour = (direction: 1 | -1) => {
    const current = series[activeIndex];
    if (!current) return;
    const target = Math.min(
      end,
      Math.max(start, current.t + direction * HOUR_MS),
    );
    const index = nearestIndex(seriesTimes, target);
    if (index >= 0) setSelectedT(series[index].t);
  };

  const onAccessibilityAction = (event: AccessibilityActionEvent) => {
    if (event.nativeEvent.actionName === 'increment') stepByHour(1);
    if (event.nativeEvent.actionName === 'decrement') stepByHour(-1);
  };

  const readoutText = inspection ? describeInspection(inspection) : '';

  return (
    <View style={{ width: '100%', gap: spacing.sm }}>
      {inspection ? (
        <View
          accessible
          accessibilityLabel={readoutText}
          accessibilityLiveRegion="polite"
          style={{ gap: spacing.xs }}
        >
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{
              ...typeRamp.headline,
              fontVariant: ['tabular-nums'],
              color: palette.textPrimary,
            }}
          >
            {inspection.isNow
              ? `Now · ${formatClockTime(inspection.t)}`
              : formatClockTime(inspection.t)}
          </Text>
          <View
            testID="caffeine-readout-values"
            style={{
              flexDirection: largeText ? 'column' : 'row',
              flexWrap: largeText ? 'nowrap' : 'wrap',
              columnGap: spacing.lg,
              rowGap: spacing.sm,
            }}
          >
            <ReadoutValue
              swatch={
                <View
                  style={{
                    width: 12,
                    height: 2,
                    borderRadius: 1,
                    backgroundColor: accent,
                  }}
                />
              }
              label="Active caffeine"
              value={`${Math.round(inspection.activeMg)} mg`}
              qualifier={inspection.isFuture ? 'Projection' : 'Model'}
            />
            <ReadoutValue
              swatch={
                <View
                  style={{
                    width: 8,
                    height: 8,
                    borderRadius: 4,
                    backgroundColor: accent,
                  }}
                />
              }
              label="Logged today"
              value={`${Math.round(inspection.loggedMg)} mg`}
              qualifier={
                inspection.loggedCount === 0
                  ? 'None logged by then'
                  : `${inspection.loggedCount} ${inspection.loggedCount === 1 ? 'dose' : 'doses'} by then`
              }
            />
            <ReadoutValue
              label="Alertness"
              value={
                inspection.alertness.status === 'estimated'
                  ? `${inspection.alertness.score}`
                  : '—'
              }
              qualifier={
                inspection.alertness.status === 'estimated'
                  ? inspection.isFuture
                    ? 'Projection'
                    : 'Estimate'
                  : 'Needs recent sleep'
              }
            />
          </View>
        </View>
      ) : null}

      <View
        accessible
        accessibilityRole={inspectable ? 'adjustable' : 'image'}
        accessibilityLabel={daySummary}
        accessibilityValue={inspectable ? { text: readoutText } : undefined}
        accessibilityHint={
          inspectable
            ? 'Swipe up or down to inspect the day an hour at a time.'
            : undefined
        }
        accessibilityActions={
          inspectable
            ? [{ name: 'increment' }, { name: 'decrement' }]
            : undefined
        }
        onAccessibilityAction={inspectable ? onAccessibilityAction : undefined}
        testID="caffeine-today-graph"
        style={{ width: '100%', height }}
        onLayout={(e) => setWidth(e.nativeEvent.layout.width)}
        {...responder.panHandlers}
      >
        {width > 0 ? (
          <View pointerEvents="none">
          <Svg width={width} height={height}>
            <Defs>
              <LinearGradient id="caffArea" x1="0" y1="0" x2="0" y2="1">
                <Stop offset="0" stopColor={accent} stopOpacity={0.14} />
                <Stop offset="1" stopColor={accent} stopOpacity={0.02} />
              </LinearGradient>
            </Defs>

            {chart.yTicks.map((tick) => (
              <Line
                key={`grid-${tick.value}`}
                x1={chart.plot.x}
                x2={chart.plot.x + chart.plot.width}
                y1={tick.y}
                y2={tick.y}
                stroke={palette.separator}
                strokeDasharray={tick.value === 0 ? undefined : [2, 6]}
                strokeWidth={1}
              />
            ))}

            <Line
              x1={chart.nowX}
              x2={chart.nowX}
              y1={chart.plot.y}
              y2={chart.baseY}
              stroke={palette.textTertiary}
              strokeOpacity={0.5}
              strokeDasharray={[3, 4]}
              strokeWidth={1}
            />

            {chart.areaPath ? (
              <Path d={chart.areaPath} fill="url(#caffArea)" />
            ) : null}
            {chart.pastPath ? (
              <Path
                d={chart.pastPath}
                stroke={accent}
                strokeWidth={2}
                fill="none"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            ) : null}
            {chart.futurePath ? (
              <Path
                d={chart.futurePath}
                stroke={accent}
                strokeOpacity={0.55}
                strokeWidth={2}
                strokeDasharray={[4, 5]}
                fill="none"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            ) : null}

            {chart.doseMarks.map((mark, i) => (
              <Circle
                key={`dose-${mark.key}-${i}`}
                cx={mark.x}
                cy={chart.baseY}
                r={DOSE_RADIUS}
                fill={accent}
                stroke={palette.card}
                strokeWidth={2}
              />
            ))}

            {selectedPoint ? (
              <>
                <Line
                  x1={selectedPoint.x}
                  x2={selectedPoint.x}
                  y1={chart.plot.y}
                  y2={chart.baseY}
                  stroke={palette.textSecondary}
                  strokeWidth={1}
                />
                <Circle
                  cx={selectedPoint.x}
                  cy={selectedPoint.y}
                  r={5}
                  fill={accent}
                  stroke={palette.card}
                  strokeWidth={2}
                />
              </>
            ) : null}
          </Svg>
          </View>
        ) : null}
        {width > 0 ? (
          <View
            pointerEvents="none"
            style={{
              position: 'absolute',
              left: 0,
              top: 0,
              width: AXIS_WIDTH,
              height,
            }}
          >
            {chart.yTicks.map((tick) => (
              <Text
                key={`tick-${tick.value}`}
                maxFontSizeMultiplier={AXIS_MAX_FONT_SCALE}
                style={{
                  position: 'absolute',
                  left: 0,
                  right: spacing.xs,
                  top: tick.y - axisLabelHeight / 2,
                  ...typeRamp.caption,
                  fontVariant: ['tabular-nums'],
                  color: palette.textTertiary,
                }}
              >
                {Math.round(tick.value)}
              </Text>
            ))}
          </View>
        ) : null}
      </View>

      <View
        importantForAccessibility="no-hide-descendants"
        accessibilityElementsHidden
        style={{ height: axisLabelHeight }}
      >
        {width > 0
          ? chart.hourTicks.map((tick) => (
              <Text
                key={`hour-${tick.t}`}
                maxFontSizeMultiplier={AXIS_MAX_FONT_SCALE}
                style={{
                  position: 'absolute',
                  left: tick.x,
                  ...typeRamp.caption,
                  color: palette.textTertiary,
                }}
              >
                {fmtHour(tick.t)}
              </Text>
            ))
          : null}
      </View>

      {inspectable && selectedIndex !== null ? (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Return to now"
          onPress={() => setSelectedT(null)}
          style={({ pressed }) => ({
            alignSelf: 'flex-start',
            minHeight: controlSizes.minimumTouchTarget,
            justifyContent: 'center',
            paddingHorizontal: spacing.sm,
            borderRadius: radii.capsule,
            backgroundColor: palette.selectionFill,
            opacity: pressed ? motion.pressedOpacity : 1,
          })}
        >
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{ ...typeRamp.subheadline, fontWeight: '600', color: palette.tint }}
          >
            Return to Now
          </Text>
        </Pressable>
      ) : null}

      {showCaption ? (
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.footnote, color: palette.textSecondary }}
        >
          Modeled with a {prefs.halfLife}-hour half-life. Dots are logged
          doses; dashes are projected.
          {inspectable ? ' Tap or drag to inspect.' : ''}
        </Text>
      ) : null}
    </View>
  );
}

function ReadoutValue({
  label,
  value,
  qualifier,
  swatch,
}: {
  label: string;
  value: string;
  qualifier: string;
  swatch?: React.ReactNode;
}) {
  const palette = getAppPalette(useAppScheme());
  return (
    <View style={{ minWidth: 92, flexShrink: 1, gap: 2 }}>
      <View
        style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xxs }}
      >
        {swatch}
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            ...typeRamp.caption,
            flexShrink: 1,
            color: palette.textSecondary,
          }}
        >
          {label}
        </Text>
      </View>
      <Text
        maxFontSizeMultiplier={fontScaling.hero}
        style={{
          ...typeRamp.title3,
          fontVariant: ['tabular-nums'],
          color: palette.textPrimary,
        }}
      >
        {value}
      </Text>
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...typeRamp.caption, color: palette.textTertiary }}
      >
        {qualifier}
      </Text>
    </View>
  );
}
