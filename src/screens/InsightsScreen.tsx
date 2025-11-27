import React, { useMemo, useState } from 'react';
import { View, Text, Pressable, PlatformColor, Share } from 'react-native';
import ScreenContainer from '~/components/ScreenContainer';
import Svg, { Path, Defs, LinearGradient, Stop, Line as SvgLine } from 'react-native-svg';
import { useStore } from '~/state/store';
import useSleepGuidance from '~/hooks/useSleepGuidance';

const CONTENT_MAX_WIDTH = 560;
const HIT_TARGET = 44;

function SectionHeader({ title }: { title: string }) {
  return (
    <Text accessibilityRole="header" style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label'), marginBottom: 8 }}>
      {title}
    </Text>
  );
}

function Panel({ children, style }: React.PropsWithChildren<{ style?: any }>) {
  return (
    <View
      style={[
        {
          backgroundColor: PlatformColor('secondarySystemBackground'),
          borderRadius: 16,
          padding: 16,
          borderWidth: 1,
          borderColor: PlatformColor('separator'),
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

function SegmentedChips<T extends string>({ options, value, onChange }: { options: { key: T; label: string }[]; value: T; onChange: (val: T) => void; }) {
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
      {options.map((o) => {
        const selected = o.key === value;
        return (
          <Pressable
            key={o.key}
            onPress={() => onChange(o.key)}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            accessibilityLabel={o.label}
            hitSlop={12}
            style={{
              minHeight: HIT_TARGET,
              paddingHorizontal: 14,
              paddingVertical: 10,
              borderRadius: 999,
              backgroundColor: selected ? PlatformColor('systemFill') : PlatformColor('tertiarySystemBackground'),
              borderWidth: 1,
              borderColor: PlatformColor('separator'),
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('label'), fontWeight: selected ? '600' : '400' }}>{o.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

type RangeKey = '7' | '14' | '30' | 'custom';

function TrendChart({ data, daysTs, height = 160, strokeWidth = 2 }: { data: number[]; daysTs?: number[]; height?: number; strokeWidth?: number }) {
  const [width, setWidth] = useState(0);
  const padding = { top: 12, right: 8, bottom: 18, left: 8 };
  const w = Math.max(0, width - padding.left - padding.right);
  const h = Math.max(0, height - padding.top - padding.bottom);
  const min = Math.min(...data, 0);
  const max = Math.max(...data, 1);
  const pad = (max - min) * 0.1;
  const yMin = min - pad;
  const yMax = max + pad;
  const toX = (i: number) => (data.length <= 1 ? 0 : (i / (data.length - 1)) * w);
  const toY = (v: number) => h - ((v - yMin) / Math.max(1e-6, (yMax - yMin))) * h;

  // Build polyline path
  let d = '';
  data.forEach((v, i) => {
    const x = padding.left + toX(i);
    const y = padding.top + toY(v);
    d += i === 0 ? `M ${x} ${y}` : ` L ${x} ${y}`;
  });
  // Area path to baseline
  let a = '';
  if (data.length > 0) {
    const x0 = padding.left + toX(0);
    const xN = padding.left + toX(data.length - 1);
    const y0 = padding.top + toY(data[0]);
    const yN = padding.top + toY(data[data.length - 1]);
    const yBase = padding.top + toY(yMin);
    a = `M ${x0} ${y0}`;
    for (let i = 1; i < data.length; i++) a += ` L ${padding.left + toX(i)} ${padding.top + toY(data[i])}`;
    a += ` L ${xN} ${yBase} L ${x0} ${yBase} Z`;
  }

  return (
    <View onLayout={(e) => setWidth(e.nativeEvent.layout.width)} style={{ width: '100%', height }}>
      {width > 0 ? (
        <Svg width={width} height={height}>
          {/* Gridlines (dashed, subtle) */}
          {Array.from({ length: 3 }).map((_, i) => {
            const y = padding.top + (i / 2) * h;
            return <SvgLine key={`h${i}`} x1={padding.left} y1={y} x2={width - padding.right} y2={y} stroke="#8E8E93" strokeOpacity={0.25} strokeWidth={1} strokeDasharray={[2,6]} />;
          })}
          {Array.from({ length: 2 }).map((_, i) => {
            const x = padding.left + ((i + 1) / 3) * w;
            return <SvgLine key={`v${i}`} x1={x} y1={padding.top} x2={x} y2={padding.top + h} stroke="#8E8E93" strokeOpacity={0.25} strokeWidth={1} strokeDasharray={[2,6]} />;
          })}
          <Defs>
            <LinearGradient id="areaGrad" x1="0" y1="0" x2="0" y2="1">
              <Stop offset={0} stopColor="#FFFFFF" stopOpacity={0.18} />
              <Stop offset={1} stopColor="#FFFFFF" stopOpacity={0.04} />
            </LinearGradient>
          </Defs>
          {/* Area fill */}
          {max - min > 0.01 && a ? <Path d={a} fill="url(#areaGrad)" /> : null}
          {/* Line glow */}
          {d ? <Path d={d} stroke="#FFFFFF" strokeOpacity={0.35} strokeWidth={strokeWidth + 2} fill="none" strokeLinejoin="round" strokeLinecap="round" /> : null}
          {/* Line */}
          {d ? <Path d={d} stroke="#FFFFFF" strokeWidth={strokeWidth} fill="none" strokeLinejoin="round" strokeLinecap="round" /> : null}
        </Svg>
      ) : null}
    </View>
  );
}

export default function InsightsScreen() {
  const doses = useStore((s) => s.doses);
  const sleeps = useStore((s) => s.sleeps);
  const dailyLimit = useStore((s) => s.prefs.dailyLimitMg ?? 400);
  const halfLife = useStore((s) => s.prefs.halfLife);
  const sleepGuidance = useSleepGuidance();

  const [range, setRange] = useState<RangeKey>('7');
  // Custom range state (inclusive of both start/end days)
  const [customStart, setCustomStart] = useState<number>(() => {
    const end = new Date();
    const start = new Date(end);
    start.setDate(end.getDate() - 6); // default last 7 days
    start.setHours(0,0,0,0);
    return start.getTime();
  });
  const [customEnd, setCustomEnd] = useState<number>(() => {
    const end = new Date();
    end.setHours(23,59,59,999);
    return end.getTime();
  });
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [sourceFilter, setSourceFilter] = useState<string[] | null>(null); // null = all
  const [weekdayFilter, setWeekdayFilter] = useState<number[] | null>(null); // 0=Sun...6=Sat, null = all

  // Date helpers (must be defined before use in hooks below)
  const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0).getTime();
  const endOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999).getTime();

  const DAYS = useMemo(() => (range === '7' ? 7 : range === '14' ? 14 : range === '30' ? 30 : Math.max(1, Math.round((endOfDay(new Date(customEnd)) - startOfDay(new Date(customStart))) / 86400000) + 1)), [range, customStart, customEnd]);
  const DAILY_LIMIT = dailyLimit; // user-configurable limit

  // Filter helpers
  const doseInFilters = (ts: number, source?: string) => {
    if (sourceFilter && source && !sourceFilter.includes(source)) return false;
    if (weekdayFilter) {
      const wd = new Date(ts).getDay();
      if (!weekdayFilter.includes(wd)) return false;
    }
    return true;
  };

  // Build daily totals for current and previous window
  const { days, totals, prevTotals } = useMemo(() => {
    const daysArr: number[] = [];
    const tot: number[] = [];
    const prev: number[] = [];

    const buildTotalsForRange = (startMs: number, endMs: number) => {
      const arr: number[] = [];
      const daysList: number[] = [];
      const start = startOfDay(new Date(startMs));
      const end = endOfDay(new Date(endMs));
      const nDays = Math.max(1, Math.round((end - start) / 86400000) + 1);
      for (let i = 0; i < nDays; i++) {
        const d = new Date(start);
        d.setDate(d.getDate() + i);
        const s = startOfDay(d), e = endOfDay(d);
        let sum = 0;
        for (const x of doses) {
          if (x.timestamp >= s && x.timestamp <= e && doseInFilters(x.timestamp, x.source)) sum += x.mg;
        }
        arr.push(sum);
        daysList.push(s);
      }
      return { arr, daysList };
    };

    if (range === 'custom') {
      const { arr, daysList } = buildTotalsForRange(customStart, customEnd);
      // previous window: same number of days ending the day before customStart
      const prevEnd = startOfDay(new Date(customStart - 1));
      const prevStart = new Date(prevEnd);
      prevStart.setDate(prevStart.getDate() - (arr.length - 1));
      const { arr: prevArr } = buildTotalsForRange(prevStart.getTime(), prevEnd);
      return { days: daysList, totals: arr, prevTotals: prevArr };
    } else {
      // rolling window ending today
      const today = new Date();
      const end = endOfDay(today);
      const start = new Date(end);
      start.setDate(start.getDate() - (DAYS - 1));
      const { arr, daysList } = buildTotalsForRange(start.getTime(), end);
      const prevEnd = startOfDay(new Date(start.getTime() - 1));
      const prevStart = new Date(prevEnd);
      prevStart.setDate(prevStart.getDate() - (DAYS - 1));
      const { arr: prevArr } = buildTotalsForRange(prevStart.getTime(), prevEnd);
      return { days: daysList, totals: arr, prevTotals: prevArr };
    }
  }, [doses, DAYS, sourceFilter, weekdayFilter, range, customStart, customEnd]);

  // Weekly average (with ≥5 days requirement)
  const { weeklyAvg, weeklyAvgCaption, deltaPctRounded } = useMemo(() => {
    const present = totals.filter((v) => v > 0).length;
    const avg = totals.reduce((a, b) => a + b, 0) / Math.max(1, totals.length);
    if (present < 5) return { weeklyAvg: undefined, weeklyAvgCaption: 'Insufficient data' };
    const prevAvg = prevTotals.reduce((a, b) => a + b, 0) / Math.max(1, prevTotals.length);
    const deltaPct = prevAvg > 0 ? ((avg / prevAvg) - 1) * 100 : undefined;
    const deltaPctRounded = deltaPct === undefined ? undefined : Math.round(deltaPct);
    const cap = deltaPct === undefined ? '—' : `${deltaPct >= 0 ? '↑' : '↓'} ${Math.abs(Math.round(deltaPct))}% vs prior ${DAYS} days`;
    return { weeklyAvg: Math.round(avg), weeklyAvgCaption: cap, deltaPctRounded };
  }, [totals, prevTotals, DAYS]);

  // Theil–Sen slope on DailyTotal (mg/day)
  const theilSenSlope = (arr: number[]) => {
    const slopes: number[] = [];
    for (let i = 0; i < arr.length; i++) {
      for (let j = i + 1; j < arr.length; j++) {
        const denom = j - i;
        if (denom !== 0) slopes.push((arr[j] - arr[i]) / denom);
      }
    }
    if (slopes.length === 0) return 0;
    slopes.sort((a, b) => a - b);
    return slopes[Math.floor(slopes.length / 2)];
  };
  const slope = useMemo(() => theilSenSlope(totals), [totals]);

  // Limit adherence and streaks
  const { adherencePct, latestStreak } = useMemo(() => {
    let withData = 0, within = 0;
    let streak = 0;
    for (let i = totals.length - 1; i >= 0; i--) {
      const v = totals[i];
      if (v > 0) {
        withData++;
        if (v <= DAILY_LIMIT) { within++; streak++; } else { streak = 0; }
      }
    }
    const pct = withData > 0 ? Math.round((within / withData) * 100) : 0;
    return { adherencePct: pct, latestStreak: streak };
  }, [totals]);

  // Daypart distribution
  const daypart = useMemo(() => {
    const bins = [0, 0, 0, 0]; // 05–11, 11–17, 17–21, 21–05
    const inRangeStart = days[0] ?? Date.now();
    const inRangeEnd = endOfDay(new Date(days[days.length - 1] ?? Date.now()));
    for (const x of doses) {
      if (x.timestamp < inRangeStart || x.timestamp > inRangeEnd) continue;
      if (!doseInFilters(x.timestamp, x.source)) continue;
      const d = new Date(x.timestamp);
      const hr = d.getHours();
      const idx = hr >= 5 && hr < 11 ? 0 : hr >= 11 && hr < 17 ? 1 : hr >= 17 && hr < 21 ? 2 : 3;
      bins[idx] += x.mg;
    }
    return bins;
  }, [doses, days, sourceFilter, weekdayFilter]);

  // Source mix
  const sourceMix = useMemo(() => {
    const inRangeStart = days[0] ?? Date.now();
    const inRangeEnd = endOfDay(new Date(days[days.length - 1] ?? Date.now()));
    const map = new Map<string, number>();
    const norm = (s?: string) => {
      if (!s) return 'Other';
      const v = s.toLowerCase();
      if (v.includes('espresso') || v.includes('drip') || v.includes('brew')) return 'Coffee';
      if (v.includes('tea') || v.includes('matcha')) return 'Tea';
      if (v.includes('energy')) return 'Energy';
      if (v.includes('pill')) return 'Pills';
      return 'Other';
    };
    for (const x of doses) {
      if (x.timestamp < inRangeStart || x.timestamp > inRangeEnd) continue;
      if (!doseInFilters(x.timestamp, x.source)) continue;
      const k = norm(x.source);
      map.set(k, (map.get(k) || 0) + x.mg);
    }
    const arr = Array.from(map.entries()).sort((a, b) => b[1] - a[1]);
    const sum = arr.reduce((a, b) => a + b[1], 0) || 1;
    return arr.map(([k, v]) => ({ k, mg: v, pct: Math.round((v / sum) * 100) }));
  }, [doses, days, sourceFilter, weekdayFilter]);

  // Sleep impact proxy (last dose before sleep)
  const lastDoseStats = useMemo(() => {
    const pairs: { deltaMin: number; sleepMin: number }[] = [];
    for (const s of sleeps) {
      const sleepStart = s.start;
      const windowStart = sleepStart - 12 * 3600000;
      let last: number | undefined;
      for (const d of doses) {
        if (d.timestamp <= sleepStart && d.timestamp >= windowStart && doseInFilters(d.timestamp, d.source)) {
          if (!last || d.timestamp > last) last = d.timestamp;
        }
      }
      if (last) {
        const deltaMin = Math.round((sleepStart - last) / 60000); // minutes earlier
        const sleepMin = Math.round((s.end - s.start) / 60000);
        pairs.push({ deltaMin, sleepMin });
      }
    }
    const n = pairs.length;
    const med = (arr: number[]) => { const a = [...arr].sort((x, y) => x - y); return a.length ? a[Math.floor(a.length / 2)] : 0; };
    const p = (arr: number[], q: number) => { const a = [...arr].sort((x, y) => x - y); const i = Math.max(0, Math.min(a.length - 1, Math.round(q * (a.length - 1)))); return a[i] || 0; };
    const deltas = pairs.map((p2) => p2.deltaMin);
    const sleepDur = pairs.map((p2) => p2.sleepMin);
    return {
      n,
      medianDeltaMin: med(deltas),
      p10: p(deltas, 0.1),
      p90: p(deltas, 0.9),
      showCorrelation: n >= 14,
      medianSleepMin: med(sleepDur),
    };
  }, [sleeps, doses, sourceFilter, weekdayFilter]);

  // Guidance: suggest bedtime based on half-life + current mg, and wake time on 90m cycles
  const guidance = useMemo(() => {
    const fmt = (ts: number) => {
      try { return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(ts)); }
      catch { return new Date(ts).toLocaleTimeString(); }
    };
    return `Suggested bedtime: ${fmt(sleepGuidance.bedtime)} (≈${sleepGuidance.mgAtBed} mg active).
Suggested wake time: ${fmt(sleepGuidance.wake)} (90‑min cycles, aim for 6–7am).`;
  }, [sleepGuidance]);

  // Mode of daily totals for compressed summaries on larger ranges
  const modeMg = useMemo(() => {
    if (!totals.length) return 0;
    const freq = new Map<number, number>();
    for (const v of totals) freq.set(v, (freq.get(v) || 0) + 1);
    let bestVal = 0, bestCount = -1;
    for (const [val, count] of freq) {
      if (count > bestCount || (count === bestCount && val < bestVal)) {
        bestVal = val; bestCount = count;
      }
    }
    return bestVal;
  }, [totals]);

  // Weekly summaries (groups of 7 consecutive days) with mode per week
  const weeklySummaries = useMemo(() => {
    const groups: { start: number; end: number; mode: number }[] = [];
    for (let i = 0; i + 6 < days.length; i += 7) {
      const start = days[i];
      const end = days[i + 6];
      const slice = totals.slice(i, i + 7);
      const freq = new Map<number, number>();
      for (const v of slice) freq.set(v, (freq.get(v) || 0) + 1);
      let bestVal = 0, bestCount = -1;
      for (const [val, count] of freq) {
        if (count > bestCount || (count === bestCount && val < bestVal)) { bestVal = val; bestCount = count; }
      }
      groups.push({ start, end, mode: bestVal });
    }
    return groups;
  }, [days, totals]);

  const fmtDay = (ts: number) => {
    try { return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(new Date(ts)); }
    catch { return new Date(ts).toDateString(); }
  };

  return (
    <ScreenContainer center>
      <View style={{ width: '100%', maxWidth: CONTENT_MAX_WIDTH, gap: 16 }}>
        {/* Range + Filters */}
        <Panel>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
            <SegmentedChips
              value={range}
              onChange={setRange}
              options={[{ key: '7', label: '7' }, { key: '14', label: '14' }, { key: '30', label: '30' }, { key: 'custom', label: 'Custom' }]}
            />
            <View style={{ flex: 1 }} />
            <Pressable
              onPress={() => setFiltersOpen((v) => !v)}
              accessibilityRole="button"
              hitSlop={12}
              style={{ minHeight: HIT_TARGET, paddingHorizontal: 12, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
            >
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('label') }}>Filter</Text>
            </Pressable>
          </View>
          {range === 'custom' ? (
            <View style={{ marginTop: 12, gap: 8 }}>
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Custom Range</Text>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
                <Text style={{ width: 56, fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Start</Text>
                <Pressable
                  onPress={() => setCustomStart((t) => { const d = new Date(t); d.setDate(d.getDate() - 1); d.setHours(0,0,0,0); return d.getTime(); })}
                  accessibilityRole="button"
                  hitSlop={12}
                  style={{ minWidth: 44, minHeight: 36, borderRadius: 8, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ color: PlatformColor('label') }}>{'<'}</Text>
                </Pressable>
                <Text style={{ flex: 1, fontSize: 15, lineHeight: 20, color: PlatformColor('label') }}>{fmtDay(customStart)}</Text>
                <Pressable
                  onPress={() => setCustomStart((t) => {
                    const next = new Date(t); next.setDate(next.getDate() + 1); next.setHours(0,0,0,0);
                    // ensure start <= end
                    const end = new Date(customEnd); end.setHours(23,59,59,999);
                    if (next.getTime() <= end.getTime()) return next.getTime();
                    return t;
                  })}
                  accessibilityRole="button"
                  hitSlop={12}
                  style={{ minWidth: 44, minHeight: 36, borderRadius: 8, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ color: PlatformColor('label') }}>{'>'}</Text>
                </Pressable>
              </View>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
                <Text style={{ width: 56, fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>End</Text>
                <Pressable
                  onPress={() => setCustomEnd((t) => {
                    const prev = new Date(t); prev.setDate(prev.getDate() - 1); prev.setHours(23,59,59,999);
                    const start = new Date(customStart); start.setHours(0,0,0,0);
                    if (prev.getTime() >= start.getTime()) return prev.getTime();
                    return t;
                  })}
                  accessibilityRole="button"
                  hitSlop={12}
                  style={{ minWidth: 44, minHeight: 36, borderRadius: 8, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ color: PlatformColor('label') }}>{'<'}</Text>
                </Pressable>
                <Text style={{ flex: 1, fontSize: 15, lineHeight: 20, color: PlatformColor('label') }}>{fmtDay(customEnd)}</Text>
                <Pressable
                  onPress={() => setCustomEnd((t) => { const d = new Date(t); d.setDate(d.getDate() + 1); d.setHours(23,59,59,999); return d.getTime(); })}
                  accessibilityRole="button"
                  hitSlop={12}
                  style={{ minWidth: 44, minHeight: 36, borderRadius: 8, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ color: PlatformColor('label') }}>{'>'}</Text>
                </Pressable>
              </View>
              <View style={{ flexDirection: 'row', gap: 8 }}>
                <Pressable
                  onPress={() => {
                    const end = new Date(); end.setHours(23,59,59,999);
                    const start = new Date(end); start.setDate(end.getDate() - 6); start.setHours(0,0,0,0);
                    setCustomStart(start.getTime()); setCustomEnd(end.getTime());
                  }}
                  accessibilityRole="button"
                  style={{ minHeight: 36, paddingHorizontal: 12, borderRadius: 8, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('systemFill') }}
                >
                  <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('label') }}>Reset 7d</Text>
                </Pressable>
              </View>
            </View>
          ) : null}
          {filtersOpen ? (
            <View style={{ marginTop: 12, gap: 8 }} accessible accessibilityRole="summary">
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Filters</Text>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
                {['Espresso', 'Drip', 'Cold Brew', 'Tea', 'Matcha', 'Energy', 'Pills', 'Other'].map((s) => {
                  const active = sourceFilter?.includes(s) ?? false;
                  return (
                    <Pressable
                      key={s}
                      onPress={() => {
                        setSourceFilter((curr) => {
                          if (!curr) return [s];
                          return curr.includes(s) ? curr.filter((x) => x !== s) : [...curr, s];
                        });
                      }}
                      accessibilityRole="button"
                      accessibilityState={{ selected: active }}
                      style={{ paddingHorizontal: 12, paddingVertical: 8, borderRadius: 8, backgroundColor: active ? PlatformColor('systemFill') : PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                    >
                      <Text style={{ color: PlatformColor('label') }}>{s}</Text>
                    </Pressable>
                  );
                })}
              </View>
              <View style={{ height: 8 }} />
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Weekdays</Text>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
                {['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map((label, idx) => {
                  const active = weekdayFilter ? weekdayFilter.includes(idx) : false;
                  return (
                    <Pressable
                      key={label}
                      onPress={() => {
                        setWeekdayFilter((curr) => {
                          if (!curr) return [idx];
                          return curr.includes(idx) ? curr.filter((x) => x !== idx) : [...curr, idx];
                        });
                      }}
                      accessibilityRole="button"
                      accessibilityState={{ selected: active }}
                      style={{ paddingHorizontal: 12, paddingVertical: 8, borderRadius: 8, backgroundColor: active ? PlatformColor('systemFill') : PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                    >
                      <Text style={{ color: PlatformColor('label') }}>{label}</Text>
                    </Pressable>
                  );
                })}
                <View style={{ width: 8 }} />
                <Pressable
                  onPress={() => { setSourceFilter(null); setWeekdayFilter(null); }}
                  accessibilityRole="button"
                  style={{ paddingHorizontal: 12, paddingVertical: 8, borderRadius: 8, backgroundColor: PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ color: PlatformColor('label') }}>Clear</Text>
                </Pressable>
              </View>
            </View>
          ) : null}
        </Panel>

        {/* Hero metrics */}
        <View style={{ flexDirection: 'row', gap: 12 }}>
          <Panel style={{ flex: 1 }}>
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Weekly Avg</Text>
            <View style={{ flexDirection: 'row', alignItems: 'flex-end', gap: 8 }}>
              <Text style={{ fontSize: 34, lineHeight: 41, fontWeight: '600', color: PlatformColor('label') }}>
                {weeklyAvg === undefined ? '—' : `${weeklyAvg}`}
              </Text>
              <Text style={{ fontSize: 22, lineHeight: 28, color: PlatformColor('secondaryLabel') }}>mg</Text>
            </View>
            <Text style={{ marginTop: 6, fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>{weeklyAvgCaption}</Text>
          </Panel>
          <Panel style={{ width: 140, alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Adherence</Text>
            <Text accessibilityRole="text" style={{ fontSize: 28, lineHeight: 34, fontWeight: '600', color: PlatformColor('label') }}>{adherencePct}%</Text>
            <Text style={{ marginTop: 6, fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>Streak {latestStreak}d</Text>
          </Panel>
        </View>

        {/* Guidance */}
        <View>
          <SectionHeader title="Guidance" />
          <Panel>
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('label') }}>{guidance}</Text>
            <Text style={{ marginTop: 6, fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
              Descriptive only. Correlation does not imply causation. All computations on-device.
            </Text>
          </Panel>
        </View>

        {/* Trend line chart with % change */}
        <View>
          <SectionHeader title={range === 'custom' ? 'Custom Trend' : `${DAYS}-Day Trend`} />
          <Panel>
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              <Text style={{ flex: 1, fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
                Last value {totals[totals.length - 1] ?? 0} mg
              </Text>
              {typeof deltaPctRounded === 'number' ? (
                <Text
                  accessibilityLabel={`Change versus prior ${DAYS} days ${deltaPctRounded >= 0 ? 'up' : 'down'} ${Math.abs(deltaPctRounded)} percent`}
                  style={{ fontSize: 15, lineHeight: 20, fontWeight: '600', color: PlatformColor('tintColor') }}
                >
                  {deltaPctRounded >= 0 ? '↑' : '↓'} {Math.abs(deltaPctRounded)}%
                </Text>
              ) : null}
            </View>
            <View style={{ marginTop: 8 }}>
              <TrendChart data={totals} daysTs={days} />
            </View>
            {/* X-axis ticks (first, middle, last) */}
            <View style={{ marginTop: 4, flexDirection: 'row' }}>
              <Text style={{ flex: 1, fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>{fmtDay(days[0] ?? Date.now())}</Text>
              <Text style={{ flex: 1, textAlign: 'center', fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>{fmtDay(days[Math.floor(days.length/2)] ?? Date.now())}</Text>
              <Text style={{ flex: 1, textAlign: 'right', fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>{fmtDay(days[days.length-1] ?? Date.now())}</Text>
            </View>
            <View accessible accessibilityRole="summary" style={{ marginTop: 8 }}>
              {range === '14' && weeklySummaries.slice(-2).map((g) => (
                <Text key={`${g.start}`} style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
                  {fmtDay(g.start)} – {fmtDay(g.end)} — {g.mode} mg (mode)
                </Text>
              ))}
              {range === '30' && weeklySummaries.slice(-3).map((g) => (
                <Text key={`${g.start}`} style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
                  {fmtDay(g.start)} – {fmtDay(g.end)} — {g.mode} mg (mode)
                </Text>
              ))}
              {range === 'custom' && (
                <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
                  {fmtDay(days[0] ?? Date.now())} – {fmtDay(days[days.length - 1] ?? Date.now())} — {modeMg} mg (mode)
                </Text>
              )}
            </View>
          </Panel>
        </View>

        {/* Daypart Distribution */}
        <View>
          <SectionHeader title="Daypart Distribution" />
          <Panel>
            {['05–11', '11–17', '17–21', '21–05'].map((label, idx) => (
              <View key={label} style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: idx === 0 ? 0 : 6 }}>
                <Text style={{ width: 64, fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>{label}</Text>
                <View style={{ flex: 1, height: 10, backgroundColor: PlatformColor('tertiarySystemBackground'), borderRadius: 6, overflow: 'hidden' }}>
                  <View style={{ width: `${Math.min(100, daypart[idx] === 0 ? 0 : Math.min(100, (daypart[idx] / Math.max(1, Math.max(...daypart))) * 100))}%`, height: '100%', backgroundColor: PlatformColor('tintColor') }} />
                </View>
                <Text style={{ width: 64, textAlign: 'right', fontSize: 15, lineHeight: 20, color: PlatformColor('label') }}>{Math.round(daypart[idx])} mg</Text>
              </View>
            ))}
          </Panel>
        </View>

        {/* Calendar Heatmap removed per request */}

        {/* (Sleep impact moved to Sleep screen) */}

        {/* Source Mix */}
        <View>
          <SectionHeader title="Source Mix" />
          <Panel>
            {sourceMix.length === 0 ? (
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>No sources in range.</Text>
            ) : (
              sourceMix.map((s) => (
                <View key={s.k} style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 6 }}>
                  <Text style={{ width: 80, fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>{s.k}</Text>
                  <View style={{ flex: 1, height: 10, backgroundColor: PlatformColor('tertiarySystemBackground'), borderRadius: 6, overflow: 'hidden' }}>
                    <View style={{ width: `${s.pct}%`, height: '100%', backgroundColor: PlatformColor('tintColor') }} />
                  </View>
                  <Text style={{ width: 80, textAlign: 'right', fontSize: 15, lineHeight: 20, color: PlatformColor('label') }}>{s.mg} mg ({s.pct}%)</Text>
                </View>
              ))
            )}
          </Panel>
        </View>

        {/* Share (placeholder) */}
        <Panel>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>Export monthly summary</Text>
            <View style={{ flex: 1 }} />
            <Pressable
              accessibilityRole="button"
              hitSlop={12}
              style={{ minHeight: HIT_TARGET, paddingHorizontal: 12, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('tintColor') }}
              onPress={async () => {
                try {
                  const startStr = fmtDay(days[0] ?? Date.now());
                  const endStr = fmtDay(days[days.length - 1] ?? Date.now());
                  const total = totals.reduce((a, b) => a + b, 0);
                  const avg = totals.length ? Math.round(total / totals.length) : 0;
                  const parts = [
                    `AURORA Summary ${startStr} – ${endStr}`,
                    `Total: ${total} mg`,
                    `Average: ${avg} mg/day`,
                    `Adherence: ${adherencePct}% (streak ${latestStreak}d)`,
                    `Dayparts: [05–11:${Math.round(daypart[0])} mg, 11–17:${Math.round(daypart[1])} mg, 17–21:${Math.round(daypart[2])} mg, 21–05:${Math.round(daypart[3])} mg]`,
                    `Sources: ${sourceMix.map((s) => `${s.k} ${s.mg}mg (${s.pct}%)`).join(', ') || '—'}`,
                  ];
                  await Share.share({ message: parts.join('\n') });
                } catch (e) {
                  // no-op
                }
              }}
            >
              <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: '#FFFFFF' }}>Share</Text>
            </Pressable>
          </View>
        </Panel>
      </View>
    </ScreenContainer>
  );
}
