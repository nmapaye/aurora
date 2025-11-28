import React, { useMemo, useState } from 'react';
import { View, Text, PlatformColor } from 'react-native';
import Svg, { Path, Defs, LinearGradient, Stop, Circle, Line } from 'react-native-svg';
import { useTodayCaffeineSeries } from '~/hooks/useTodayCaffeineSeries';

export default function CaffeineTodayGraph() {
  const { series, start, end } = useTodayCaffeineSeries();
  const [width, setWidth] = useState(0);
  const height = 180;
  const padding = { top: 12, right: 14, bottom: 28, left: 44 };
  const accent = '#FFFFFF';
  const domain = Math.max(1, end - start);

  const { linePath, areaPath, points, nowX, yTicks } = useMemo(() => {
    if (!series.length || width === 0) {
      return { linePath: '', areaPath: '', points: [] as { x: number; y: number }[], nowX: undefined as number | undefined, yTicks: [] as { value: number; y: number }[] };
    }

    const w = Math.max(0, width - padding.left - padding.right);
    const h = Math.max(0, height - padding.top - padding.bottom);
    const vals = series.map((p) => p.mg);
    const minVal = Math.min(...vals, 0);
    const maxVal = Math.max(...vals, 10);
    const pad = (maxVal - minVal || 1) * 0.12;
    const yMin = minVal - pad;
    const yMax = maxVal + pad;
    const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

    const pts = series.map((p) => {
      const x = padding.left + clamp(((p.t - start) / domain) * w, 0, w);
      const y = padding.top + (h - ((p.mg - yMin) / Math.max(1e-6, yMax - yMin)) * h);
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
      const baseY = padding.top + h;
      a = `M ${pts[0].x} ${pts[0].y}`;
      for (let i = 1; i < pts.length; i++) a += ` L ${pts[i].x} ${pts[i].y}`;
      a += ` L ${pts[pts.length - 1].x} ${baseY} L ${pts[0].x} ${baseY} Z`;
    }

    const now = Date.now();
    const nowX = padding.left + clamp(((now - start) / domain) * w, 0, w);

    const rawTicks = [yMax, yMin + (yMax - yMin) / 2, yMin];
    const uniq = Array.from(new Set(rawTicks.map((v) => Math.round(v))));
    const yTicks = uniq.map((v) => ({
      value: v,
      y: padding.top + (h - ((v - yMin) / Math.max(1e-6, yMax - yMin)) * h),
    }));

    return { linePath: d, areaPath: a, points: pts, nowX, yTicks };
  }, [series, width, start, domain, padding.left, padding.right, padding.top, padding.bottom, height]);

  const fmtHour = (ts: number) => {
    try { return new Intl.DateTimeFormat(undefined, { hour: 'numeric' }).format(new Date(ts)); }
    catch { return new Date(ts).getHours().toString(); }
  };

  const firstTs = series[0]?.t ?? start;
  const midTs = start + domain / 2;
  const lastTs = end;

  return (
    <View style={{ width: '100%' }}>
      <View style={{ width: '100%', height, position: 'relative' }} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
        {width > 0 ? (
          <Svg width={width} height={height}>
            <Defs>
              <LinearGradient id="caffArea" x1="0" y1="0" x2="0" y2="1">
                <Stop offset="0" stopColor={accent as string} stopOpacity={0.16} />
                <Stop offset="1" stopColor={accent as string} stopOpacity={0.04} />
              </LinearGradient>
            </Defs>

            {/* Grid */}
            {Array.from({ length: 3 }).map((_, i) => {
              const y = padding.top + (i / 2) * (height - padding.top - padding.bottom);
              return <Line key={`g-h-${i}`} x1={padding.left} x2={width - padding.right} y1={y} y2={y} stroke="#8E8E93" strokeOpacity={0.18} strokeDasharray={[3, 6]} strokeWidth={1} />;
            })}

            {/* Now marker */}
            {typeof nowX === 'number' ? (
              <Line
                x1={nowX}
                x2={nowX}
                y1={padding.top}
                y2={height - padding.bottom}
                stroke={accent as string}
                strokeOpacity={0.35}
                strokeDasharray={[4, 4]}
                strokeWidth={2}
              />
            ) : null}

            {/* Area */}
            {areaPath ? <Path d={areaPath} fill="url(#caffArea)" /> : null}

            {/* Line glow + line */}
            {linePath ? <Path d={linePath} stroke={accent as string} strokeOpacity={0.32} strokeWidth={4} fill="none" strokeLinecap="round" strokeLinejoin="round" /> : null}
            {linePath ? <Path d={linePath} stroke={accent as string} strokeWidth={2.5} fill="none" strokeLinecap="round" strokeLinejoin="round" /> : null}

            {/* Points only where a dose exists */}
            {series.map((p, i) => p.hasDose ? (
              <Circle key={`pt-${i}`} cx={points[i]?.x ?? 0} cy={points[i]?.y ?? 0} r={4} fill={accent as string} stroke="#ffffff" strokeWidth={1.5} />
            ) : null)}
          </Svg>
        ) : null}
        {width > 0 && yTicks.length ? (
          <View pointerEvents="none" style={{ position: 'absolute', left: 0, top: 0, bottom: padding.bottom, width: padding.left - 8 }}>
            {yTicks.map((t, i) => {
              const y = Math.min(height - padding.bottom, Math.max(0, t.y));
              return (
                <Text
                  key={`tick-${i}-${t.value}`}
                  style={{ position: 'absolute', left: 4, top: y - 8, fontSize: 12, lineHeight: 16, color: PlatformColor('secondaryLabel') }}
                >
                  {Math.round(t.value)} mg
                </Text>
              );
            })}
          </View>
        ) : null}
      </View>
      <View style={{ flexDirection: 'row', marginTop: 6 }}>
        <Text style={{ flex: 1, fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>{fmtHour(firstTs)}</Text>
        <Text style={{ flex: 1, textAlign: 'center', fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>{fmtHour(midTs)}</Text>
        <Text style={{ flex: 1, textAlign: 'right', fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>{fmtHour(lastTs)}</Text>
      </View>
      <Text style={{ marginTop: 4, fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
        Active caffeine (mg) projected hourly based on your doses and half-life.
      </Text>
    </View>
  );
}
