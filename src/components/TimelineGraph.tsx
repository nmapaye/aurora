import React, { useMemo, useState } from 'react';
import { View, PlatformColor } from 'react-native';
import Svg, { Path, Defs, LinearGradient, Stop, Circle, Line } from 'react-native-svg';
import { useAlertnessSeries } from '~/hooks/useAlertnessSeries';

export default function TimelineGraph() {
  const { series = [] } = useAlertnessSeries() || {};
  const [width, setWidth] = useState(0);
  const height = 140;
  const padding = { top: 12, right: 12, bottom: 18, left: 12 };

  const { linePath, areaPath, points } = useMemo(() => {
    if (!series.length || width === 0) return { linePath: '', areaPath: '', points: [] as { x: number; y: number }[] };
    const w = Math.max(0, width - padding.left - padding.right);
    const h = Math.max(0, height - padding.top - padding.bottom);
    const minVal = Math.min(...series.map((p: any) => p.score ?? 0), 0);
    const maxVal = Math.max(...series.map((p: any) => p.score ?? 0), 100);
    const pad = (maxVal - minVal || 1) * 0.12;
    const yMin = minVal - pad;
    const yMax = maxVal + pad;

    const pts = series.map((p: any, i: number) => {
      const x = padding.left + (series.length <= 1 ? 0 : (i / (series.length - 1)) * w);
      const y = padding.top + (h - ((p.score - yMin) / Math.max(1e-6, yMax - yMin)) * h);
      return { x, y };
    });

    // Smooth path using simple quadratic curves (Recharts-like soft corners)
    let d = '';
    pts.forEach((pt, i) => {
      if (i === 0) {
        d = `M ${pt.x} ${pt.y}`;
      } else {
        const prev = pts[i - 1];
        const midX = (prev.x + pt.x) / 2;
        const midY = (prev.y + pt.y) / 2;
        d += ` Q ${prev.x} ${prev.y} ${midX} ${midY}`;
        if (i === pts.length - 1) {
          d += ` T ${pt.x} ${pt.y}`;
        }
      }
    });

    // Area baseline
    let a = '';
    if (pts.length > 1) {
      const baseY = padding.top + h;
      a = `M ${pts[0].x} ${pts[0].y}`;
      for (let i = 1; i < pts.length; i++) a += ` L ${pts[i].x} ${pts[i].y}`;
      a += ` L ${pts[pts.length - 1].x} ${baseY} L ${pts[0].x} ${baseY} Z`;
    }

    return { linePath: d, areaPath: a, points: pts };
  }, [series, width]);

  const accent = PlatformColor ? PlatformColor('tintColor') : '#4e91ff';

  return (
    <View style={{ width: '100%', height }} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
      {width > 0 && (
        <Svg width={width} height={height}>
          <Defs>
            <LinearGradient id="areaFade" x1="0" y1="0" x2="0" y2="1">
              <Stop offset="0" stopColor={accent as string} stopOpacity={0.18} />
              <Stop offset="1" stopColor={accent as string} stopOpacity={0.04} />
            </LinearGradient>
          </Defs>

          {/* Subtle grid */}
          {Array.from({ length: 3 }).map((_, i) => {
            const y = padding.top + (i / 2) * (height - padding.top - padding.bottom);
            return <Line key={`g-h-${i}`} x1={padding.left} x2={width - padding.right} y1={y} y2={y} stroke="#8E8E93" strokeOpacity={0.18} strokeDasharray={[3, 6]} strokeWidth={1} />;
          })}

          {/* Area */}
          {areaPath ? <Path d={areaPath} fill="url(#areaFade)" /> : null}

          {/* Line glow + line */}
          {linePath ? <Path d={linePath} stroke={accent as string} strokeOpacity={0.35} strokeWidth={4} fill="none" strokeLinecap="round" strokeLinejoin="round" /> : null}
          {linePath ? <Path d={linePath} stroke={accent as string} strokeWidth={2.5} fill="none" strokeLinecap="round" strokeLinejoin="round" /> : null}

          {/* Dots */}
          {points.map((p, i) => (
            <Circle key={`pt-${i}`} cx={p.x} cy={p.y} r={4} fill={accent as string} stroke="#ffffff" strokeWidth={1.5} />
          ))}
        </Svg>
      )}
    </View>
  );
}
