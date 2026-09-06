import ChartTable from './ChartTable';
import React, { useMemo, useState } from 'react';
import { View, Text } from 'react-native';
import Svg, { Path, Defs, LinearGradient, Stop, Line } from 'react-native-svg';
import useAppScheme from '~/hooks/useAppScheme';
import { useTodayCaffeineSeries } from '~/hooks/useTodayCaffeineSeries';
import { getAppPalette } from '~/theme/colors';
import { spacing, typeRamp } from '~/theme/tokens';

export default function CaffeineTodayGraph({
  height = 180,
  showCaption = true,
  compact = false,
  variant = 'standard',
}: {
  height?: number;
  showCaption?: boolean;
  compact?: boolean;
  variant?: 'standard' | 'panel';
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const { series, start, end } = useTodayCaffeineSeries();
  const [width, setWidth] = useState(0);
  const axisWidth = variant === 'panel' ? 54 : compact ? 42 : 52;
  const doseMarkerOffsetX = variant === 'panel' ? 12 : 8;
  const plotPadding = {
    top: variant === 'panel' ? 18 : 12,
    right: variant === 'panel' ? 6 : 14,
    bottom: compact ? 18 : 28,
    left: 0,
  };
  const accent = palette.tint;
  const domain = Math.max(1, end - start);

  const { linePath, areaPath, points, nowX, yTicks, plotRect } = useMemo(() => {
    const plotRect = {
      x: axisWidth,
      y: plotPadding.top,
      width: Math.max(0, width - axisWidth - plotPadding.right),
      height: Math.max(0, height - plotPadding.top - plotPadding.bottom),
    };

    if (!series.length || width === 0) {
      return {
        linePath: '',
        areaPath: '',
        points: [] as { x: number; y: number }[],
        nowX: undefined as number | undefined,
        yTicks: [] as { value: number; y: number }[],
        plotRect,
      };
    }

    const vals = series.map((p) => p.mg);
    const minVal = Math.min(...vals, 0);
    const maxVal = Math.max(...vals, 10);
    const pad = (maxVal - minVal || 1) * 0.12;
    const yMin = minVal - pad;
    const yMax = maxVal + pad;
    const clamp = (n: number, lo: number, hi: number) =>
      Math.min(hi, Math.max(lo, n));

    const pts = series.map((p) => {
      const x =
        plotRect.x +
        clamp(((p.t - start) / domain) * plotRect.width, 0, plotRect.width);
      const y =
        plotRect.y +
        (plotRect.height -
          ((p.mg - yMin) / Math.max(1e-6, yMax - yMin)) * plotRect.height);
      return { x, y };
    });

    let d = '';
    pts.forEach((pt, i) => {
      if (i === 0) {
        d = `M ${pt.x} ${pt.y}`;
      } else {
        const prev = pts[i - 1];
        const midX = (prev.x + pt.x) / 2;
        const midY = (prev.y + pt.y) / 2;
        d += ` Q ${prev.x} ${prev.y} ${midX} ${midY}`;
        if (i === pts.length - 1) d += ` T ${pt.x} ${pt.y}`;
      }
    });

    let a = '';
    if (pts.length > 1) {
      const baseY = plotRect.y + plotRect.height;
      a = d;
      a += ` L ${pts[pts.length - 1].x} ${baseY} L ${pts[0].x} ${baseY} Z`;
    }

    const now = Date.now();
    const nowX =
      plotRect.x +
      clamp(((now - start) / domain) * plotRect.width, 0, plotRect.width);

    const rawTicks = [yMax, yMin + (yMax - yMin) / 2, yMin];
    const uniq = Array.from(new Set(rawTicks.map((v) => Math.round(v))));
    const yTicks = uniq.map((v) => ({
      value: v,
      y:
        plotRect.y +
        (plotRect.height -
          ((v - yMin) / Math.max(1e-6, yMax - yMin)) * plotRect.height),
    }));

    return { linePath: d, areaPath: a, points: pts, nowX, yTicks, plotRect };
  }, [
    axisWidth,
    domain,
    height,
    plotPadding.bottom,
    plotPadding.right,
    plotPadding.top,
    series,
    start,
    width,
  ]);

  const fmtHour = (ts: number) => {
    try {
      return new Intl.DateTimeFormat(undefined, { hour: 'numeric' }).format(
        new Date(ts),
      );
    } catch {
      return new Date(ts).getHours().toString();
    }
  };

  const firstTs = series[0]?.t ?? start;
  const midTs = start + domain / 2;
  const lastTs = end;

  return (
    <View style={{ width: '100%' }}>
      <View
        style={{ width: '100%', height, position: 'relative' }}
        onLayout={(e) => setWidth(e.nativeEvent.layout.width)}
      >
        {width > 0 ? (
          <Svg width={width} height={height}>
            <Defs>
              <LinearGradient id="caffArea" x1="0" y1="0" x2="0" y2="1">
                <Stop
                  offset="0"
                  stopColor={accent as string}
                  stopOpacity={0.16}
                />
                <Stop
                  offset="1"
                  stopColor={accent as string}
                  stopOpacity={0.04}
                />
              </LinearGradient>
            </Defs>

            {/* Grid */}
            {yTicks.map((tick, i) => (
              <Line
                key={`g-h-${i}-${tick.value}`}
                x1={plotRect.x}
                x2={plotRect.x + plotRect.width}
                y1={tick.y}
                y2={tick.y}
                stroke={palette.separator}
                strokeDasharray={[3, 6]}
                strokeWidth={1}
              />
            ))}

            {/* Now marker */}
            {typeof nowX === 'number' ? (
              <Line
                x1={nowX}
                x2={nowX}
                y1={plotRect.y}
                y2={plotRect.y + plotRect.height}
                stroke={accent as string}
                strokeOpacity={0.35}
                strokeDasharray={[4, 4]}
                strokeWidth={2}
              />
            ) : null}

            {/* Area */}
            {areaPath ? <Path d={areaPath} fill="url(#caffArea)" /> : null}

            {/* Line glow + line */}
            {linePath ? (
              <Path
                d={linePath}
                stroke={accent as string}
                strokeOpacity={0.32}
                strokeWidth={4}
                fill="none"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            ) : null}
            {linePath ? (
              <Path
                d={linePath}
                stroke={accent as string}
                strokeWidth={2.5}
                fill="none"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            ) : null}

            {/* Vertical markers where a dose was logged */}
            {series.map((p, i) =>
              p.hasDose ? (
                <Line
                  key={`dose-${i}`}
                  x1={Math.max(
                    plotRect.x,
                    (points[i]?.x ?? plotRect.x) - doseMarkerOffsetX,
                  )}
                  x2={Math.max(
                    plotRect.x,
                    (points[i]?.x ?? plotRect.x) - doseMarkerOffsetX,
                  )}
                  y1={plotRect.y}
                  y2={plotRect.y + plotRect.height}
                  stroke={accent as string}
                  strokeOpacity={0.32}
                  strokeDasharray={[2, 7]}
                  strokeWidth={2}
                />
              ) : null,
            )}
          </Svg>
        ) : null}
        {width > 0 && yTicks.length ? (
          <View
            pointerEvents="none"
            style={{
              position: 'absolute',
              left: 0,
              top: 0,
              width: axisWidth,
              height,
            }}
          >
            {yTicks.map((t, i) => {
              const y = Math.min(
                plotRect.y + plotRect.height,
                Math.max(plotRect.y, t.y),
              );
              return (
                <Text
                  key={`tick-${i}-${t.value}`}
                  style={{
                    position: 'absolute',
                    left: 0,
                    right: 10,
                    top: y - 17,
                    ...typeRamp.caption,
                    color: palette.textSecondary,
                    textAlign: 'left',
                  }}
                >
                  {Math.round(t.value)}
                  {'\n'}mg
                </Text>
              );
            })}
          </View>
        ) : null}
      </View>
      {!compact ? (
        <View style={{ flexDirection: 'row', marginTop: spacing.xs }}>
          <Text
            style={{
              flex: 1,
              ...typeRamp.footnote,
              color: palette.textSecondary,
            }}
          >
            {fmtHour(firstTs)}
          </Text>
          <Text
            style={{
              flex: 1,
              textAlign: 'center',
              ...typeRamp.footnote,
              color: palette.textSecondary,
            }}
          >
            {fmtHour(midTs)}
          </Text>
          <Text
            style={{
              flex: 1,
              textAlign: 'right',
              ...typeRamp.footnote,
              color: palette.textSecondary,
            }}
          >
            {fmtHour(lastTs)}
          </Text>
        </View>
      ) : null}
      <ChartTable
        title="active caffeine"
        rows={series.map(
          (p) =>
            `${new Date(p.t).toLocaleString()}: ${p.mg.toFixed(1)} mg modeled active caffeine`,
        )}
      />
      {showCaption ? (
        <Text
          style={{
            marginTop: spacing.xxs,
            ...typeRamp.footnote,
            color: palette.textSecondary,
          }}
        >
          Active caffeine (mg) projected hourly based on your doses and
          half-life.
        </Text>
      ) : null}
    </View>
  );
}
