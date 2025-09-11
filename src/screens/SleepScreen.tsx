import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, Pressable, PlatformColor, ActivityIndicator, Platform } from 'react-native';
import ScreenContainer from '~/components/ScreenContainer';
import { Ionicons } from '@expo/vector-icons';
import AppleHealth from '~/services/platform/health/appleHealth';
import { useStore } from '~/state/store';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';

const HIT_TARGET = 44;

function SectionHeader({ title, icon }: { title: string; icon?: string }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 8 }}>
      {icon ? <Ionicons name={icon as any} size={18} color={PlatformColor('secondaryLabel') as any} /> : null}
      <Text accessibilityRole="header" style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>
        {title}
      </Text>
    </View>
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

type SleepSample = { start: number; end: number; type?: string };

function fmtTime(ts?: number) {
  if (!ts) return '—';
  try { return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(ts)); }
  catch { return new Date(ts).toLocaleTimeString(); }
}
function fmtDate(ts?: number) {
  if (!ts) return '—';
  try { return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(new Date(ts)); }
  catch { return new Date(ts).toDateString(); }
}
function fmtDuration(ms: number){
  const h = Math.floor(ms/3600000), m = Math.round((ms%3600000)/60000);
  return `${h}h ${m}m`;
}

export default function SleepScreen() {
  const doses = useStore(s=>s.doses);
  const addDose = useStore(s=>s.addDose);
  const cutoff = useCaffeineCutoff();

  const [healthAvailable, setHealthAvailable] = useState(false);
  const [healthAuthorized, setHealthAuthorized] = useState<boolean|undefined>(undefined);
  const [loading, setLoading] = useState(false);
  const [lastSleep, setLastSleep] = useState<SleepSample|undefined>();
  const [sleepSamples, setSleepSamples] = useState<SleepSample[]>([]);
  const [wakeTime, setWakeTime] = useState<number|undefined>();
  const [error, setError] = useState<string|undefined>();

  // Optional require helper to avoid Metro static analysis of string literals
  const optionalRequire = (name: string): any | null => {
    try {
      // Use eval to keep Metro from resolving at bundle time
      // eslint-disable-next-line no-eval
      const rq = eval('require');
      return rq(name);
    } catch {
      return null;
    }
  };

  // Detect Health module availability (iOS only)
  useEffect(()=>{
    if (Platform.OS !== 'ios') { setHealthAvailable(false); return; }
    const maybe = optionalRequire('react-native-health');
    const alt = optionalRequire('react-native-apple-healthkit');
    setHealthAvailable(!!(maybe || alt));
  }, []);

  const todayTotals = useMemo(()=>{
    const now = new Date();
    const key = (d: Date) => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
    const todayKey = key(now);
    let total = 0;
    for (const d of doses){
      const k = key(new Date(d.timestamp));
      if (k===todayKey) total += d.mg;
    }
    return total;
  }, [doses]);

  // Simple recommendation engine: propose spaced doses until cutoff under a soft 200mg budget
  const plan = useMemo(()=>{
    const BUDGET = 200;
    if (!wakeTime || !cutoff?.nextCutoff) return [] as { t:number; mg:number; label:string }[];
    const start = Math.max(wakeTime + 30*60*1000, Date.now()); // first dose ~30m after wake, not in past
    const end = cutoff.nextCutoff;
    if (end <= start) return [];
    const windowH = (end - start)/3600000;
    const slots = Math.max(1, Math.min(3, Math.floor(windowH/3.5)+1));
    const base = [80, 80, 40];
    const times: number[] = [];
    for (let i=0;i<slots;i++){
      const t = start + i*3.5*3600000;
      if (t < end) times.push(t);
    }
    const remaining = Math.max(0, BUDGET - todayTotals);
    const recs: { t:number; mg:number; label:string }[] = [];
    let used = 0;
    for(let i=0;i<times.length;i++){
      let mg = base[i] ?? 40;
      if (used + mg > remaining) mg = Math.max(0, remaining - used);
      if (mg < 20) break; // too small to suggest
      used += mg;
      recs.push({ t: times[i], mg, label: i===0? 'Kickstart' : i===1? 'Sustain' : 'Top‑up' });
      if (used >= remaining) break;
    }
    return recs;
  }, [wakeTime, cutoff?.nextCutoff, todayTotals]);

  const connectHealth = async()=>{
    setError(undefined);
    setLoading(true);
    try {
      if (Platform.OS !== 'ios') { throw new Error('Health is only available on iOS.'); }
      const available = await AppleHealth.isAvailable();
      if (!available) {
        setError('HealthKit not available on this device.');
        setHealthAuthorized(false);
        return;
      }
      const ok = await AppleHealth.requestAuthorization();
      if (!ok) {
        setError('Authorization was not granted.');
        setHealthAuthorized(false);
        return;
      }
      setHealthAuthorized(true);
      const end = Date.now();
      const start = end - 3 * 24 * 3600 * 1000;
      const samples = await AppleHealth.getSleepSamples(start, end);
      const mapped: SleepSample[] = (samples || [])
        .map((s: any) => ({ start: +s.start, end: +s.end, type: s.label }))
        .filter((s) => Number.isFinite(s.start) && Number.isFinite(s.end))
        .sort((a, b) => b.end - a.end);
      const last = mapped[0];
      setSleepSamples(mapped);
      setLastSleep(last);
      setWakeTime(last?.end);
    } catch (e: any) {
      setError(e?.message || 'Failed to read sleep data.');
      setHealthAuthorized(false);
    } finally {
      setLoading(false);
    }
  };

  // Compute last night's total asleep (aggregate stages) in a 6pm–noon window
  const lastNightTotalMs = useMemo(()=>{
    if (!sleepSamples.length) return 0;
    const refEnd = (lastSleep?.end ?? sleepSamples[0]?.end);
    if (!refEnd) return 0;
    const windowEnd = new Date(refEnd);
    // End window at local noon of the wake day
    windowEnd.setHours(12,0,0,0);
    // If wake was after noon, still use noon; overlap function will cap
    const windowStart = new Date(windowEnd);
    windowStart.setDate(windowStart.getDate()-1);
    windowStart.setHours(18,0,0,0);
    const startMs = windowStart.getTime();
    const endMs = windowEnd.getTime();
    const isAsleep = (t?: string) => {
      if (!t) return false;
      const v = String(t).toUpperCase();
      return v.includes('ASLEEP') || v === 'SLEEP' || v === 'ASLEEP';
    };
    let total = 0;
    for (const s of sleepSamples){
      if (!isAsleep(s.type)) continue;
      const a = Math.max(s.start, startMs);
      const b = Math.min(s.end, endMs);
      if (b > a) total += (b - a);
    }
    return total;
  }, [sleepSamples, lastSleep?.end]);

  const addNow = (mg:number)=>{
    const id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    addDose({ id, timestamp: Date.now(), mg, source: 'Plan' });
  };

  // Sleep impact: last dose timing vs sleep onset for imported samples
  const sleepImpact = useMemo(() => {
    const pairs: { deltaMin: number; sleepMin: number }[] = [];
    for (const s of sleepSamples) {
      const sleepStart = s.start;
      const windowStart = sleepStart - 12 * 3600000;
      let last: number | undefined;
      for (const d of doses) {
        if (d.timestamp <= sleepStart && d.timestamp >= windowStart) {
          if (!last || d.timestamp > last) last = d.timestamp;
        }
      }
      if (last) {
        const deltaMin = Math.round((sleepStart - last) / 60000);
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
  }, [sleepSamples, doses]);

  return (
    <ScreenContainer horizontalPadding={16} topPadding={12} bottomPadding={32}>
      <View style={{ gap:16 }}>
        {/* Health connection */}
        <Panel>
          <Text style={{ fontSize: 22, lineHeight: 28, fontWeight: '600', color: PlatformColor('label') }}>Sleep</Text>
          <Text style={{ marginTop: 4, fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
            Import sleep from the Health app to tailor your caffeine plan.
          </Text>
          <View style={{ height: 12 }} />
          {loading ? (
            <View style={{ flexDirection:'row', alignItems:'center', gap:8 }}>
              <ActivityIndicator />
              <Text style={{ color: PlatformColor('secondaryLabel') }}>Connecting…</Text>
            </View>
          ) : (
            <Pressable
              onPress={connectHealth}
              accessibilityRole="button"
              style={{ minHeight: HIT_TARGET, borderRadius: 12, alignItems:'center', justifyContent:'center', backgroundColor: PlatformColor('tintColor') }}
            >
              <Text style={{ fontSize:17, lineHeight:22, fontWeight:'600', color: '#FFFFFF' }}>
                {healthAuthorized ? 'Refresh Sleep' : 'Connect to Health'}
              </Text>
            </Pressable>
          )}
          {error ? <Text style={{ marginTop:8, color: PlatformColor('systemRed') }}>{error}</Text> : null}
        </Panel>

        {/* Last sleep summary */}
        <View>
          <SectionHeader title="Sleep History" icon="moon" />
          <Panel>
            {lastSleep ? (
              <>
                <Text style={{ fontSize:17, lineHeight:22, color: PlatformColor('label') }}>
                  {fmtDate(lastSleep.start)} · {fmtTime(lastSleep.start)} – {fmtTime(lastSleep.end)} ({fmtDuration(lastSleep.end - lastSleep.start)})
                </Text>
                <Text style={{ marginTop:4, fontSize:15, lineHeight:20, color: PlatformColor('secondaryLabel') }}>
                  Total asleep last night: {fmtDuration(lastNightTotalMs)}
                </Text>
                <Text style={{ marginTop:4, fontSize:13, lineHeight:18, color: PlatformColor('secondaryLabel') }}>
                  Woke at {fmtTime(lastSleep.end)}
                </Text>
              </>
            ) : (
              <Text style={{ fontSize:15, lineHeight:20, color: PlatformColor('secondaryLabel') }}>
                Not connected yet. Connect to Health to import recent sleep.
              </Text>
            )}
          </Panel>
        </View>

        {/* Sleep Impact */}
        <View>
          <SectionHeader title="Caffeine Impact" icon="pulse-outline" />
          <Panel>
            {sleepImpact.n >= 1 ? (
              <>
                <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>
                  Last dose timing: {Math.round(sleepImpact.medianDeltaMin)} min before sleep
                </Text>
                <Text style={{ marginTop: 4, fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
                  P10 {sleepImpact.p10} • P90 {sleepImpact.p90}
                </Text>
                {!sleepImpact.showCorrelation ? (
                  <Text style={{ marginTop: 4, fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
                    Not enough nights for correlation (need ≥14).
                  </Text>
                ) : null}
              </>
            ) : (
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
                Not connected yet. Connect to Health to import recent sleep.
              </Text>
            )}
          </Panel>
        </View>

        {/* Recommended plan */}
        <View>
          <SectionHeader title="Recommended Plan" icon="timer-outline" />
          <Panel>
            {(!wakeTime || plan.length===0) ? (
              <Text style={{ fontSize:15, lineHeight:20, color: PlatformColor('secondaryLabel') }}>
                A plan will appear after importing your latest wake time and before today’s cutoff.
              </Text>
            ) : (
              <>
                {plan.map((p, idx)=> (
                  <View key={p.t} style={{ paddingVertical:10, borderTopWidth: idx===0?0:1, borderColor: PlatformColor('separator') }}>
                    <Text style={{ fontSize:17, lineHeight:22, color: PlatformColor('label') }}>{p.label}: {p.mg} mg at {fmtTime(p.t)}</Text>
                    {idx===0 ? (
                      <Pressable
                        onPress={()=> addNow(p.mg)}
                        accessibilityRole="button"
                        style={{ marginTop:8, alignSelf:'flex-start', minHeight:36, paddingHorizontal:12, borderRadius:8, alignItems:'center', justifyContent:'center', backgroundColor: PlatformColor('systemFill') }}
                      >
                        <Text style={{ fontSize:13, lineHeight:18, color: PlatformColor('label') }}>Log first dose now</Text>
                      </Pressable>
                    ) : null}
                  </View>
                ))}
                <Text style={{ marginTop:8, fontSize:13, lineHeight:18, color: PlatformColor('tertiaryLabel') }}>
                  Based on a soft 200 mg daily budget and your wake → cutoff window.
                </Text>
              </>
            )}
          </Panel>
        </View>
      </View>
    </ScreenContainer>
  );
}
