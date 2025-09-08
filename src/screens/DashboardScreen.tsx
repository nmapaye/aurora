import React, { useMemo } from 'react';
import { ScrollView, View, Text, Pressable, useColorScheme, PlatformColor } from 'react-native';
import { useStore } from '~/state/store';
import { useAlertnessSeries } from '~/hooks/useAlertnessSeries';
import useNextDip from '~/hooks/useNextDip';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';

const CONTENT_MAX_WIDTH = 560;
const HIT_TARGET = 44;

function SectionHeader({ title }: { title: string }) {
  return (
    <Text
      accessibilityRole="header"
      style={{
        fontSize: 17,
        lineHeight: 22,
        fontWeight: '600',
        color: PlatformColor('label'),
        marginBottom: 8,
      }}
    >
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

function MetricTile({ title, value, right }: { title: string; value: string; right?: React.ReactNode }) {
  return (
    <View
      style={{
        flex: 1,
        minHeight: HIT_TARGET,
        padding: 12,
        borderRadius: 12,
        backgroundColor: PlatformColor('tertiarySystemBackground'),
        borderWidth: 1,
        borderColor: PlatformColor('separator'),
      }}
    >
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>{title}</Text>
          <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>{value}</Text>
        </View>
        {right}
      </View>
    </View>
  );
}

function QuickAddGrid({ onAdd, onCustom }: { onAdd: (mg: number) => void; onCustom: () => void }) {
  const presets = [40, 80, 120, 200];
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 12 }}>
      {presets.map((mg) => (
        <Pressable
          key={mg}
          onPress={() => onAdd(mg)}
          accessibilityRole="button"
          accessibilityLabel={`Add ${mg} milligrams`}
          hitSlop={12}
          style={{
            minHeight: HIT_TARGET,
            minWidth: 88,
            paddingHorizontal: 14,
            paddingVertical: 10,
            borderRadius: 12,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: PlatformColor('secondarySystemBackground'),
            borderWidth: 1,
            borderColor: PlatformColor('separator'),
          }}
        >
          <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>{mg} mg</Text>
        </Pressable>
      ))}
      <Pressable
        onPress={onCustom}
        accessibilityRole="button"
        accessibilityLabel="Custom add"
        hitSlop={12}
        style={{
          minHeight: HIT_TARGET,
          minWidth: 88,
          paddingHorizontal: 14,
          paddingVertical: 10,
          borderRadius: 12,
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: PlatformColor('secondarySystemBackground'),
          borderWidth: 1,
          borderColor: PlatformColor('separator'),
        }}
      >
        <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>Custom…</Text>
      </Pressable>
    </View>
  );
}

function TimelineItem({ amount, source, time }: { amount: string; source?: string; time: string }) {
  const label = `${amount}${source ? ` ${source}` : ''} at ${time}`;
  return (
    <View
      accessible
      accessibilityRole="summary"
      accessibilityLabel={label}
      style={{ paddingVertical: 10, minHeight: HIT_TARGET }}
    >
      <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>{amount}</Text>
      <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
        {source ? `${source} • ${time}` : time}
      </Text>
    </View>
  );
}

const fmtTime = (ts: unknown) => {
  const d =
    typeof ts === 'number' ? new Date(ts) :
    typeof ts === 'string' ? new Date(ts) :
    null;
  if (!d || Number.isNaN(+d)) return '—';
  try {
    return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(d);
  } catch {
    return d.toLocaleTimeString();
  }
};

export default function DashboardScreen() {
  const scheme = useColorScheme();
  const { nowScore, mgActiveNow: mgActive, series } = (useAlertnessSeries() as any) || {};
  const nextDip: number | undefined = (useNextDip as any)?.() as any;
  const cutoff = useCaffeineCutoff();

  const doses = useStore((s) => s.doses);
  const addDose = useStore((s) => s.addDose);

  const { todayTotal, yesterdayTotal, deltaText, todayDoses } = useMemo(() => {
    const now = new Date();
    const key = (d: Date) => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
    const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0).getTime();
    const endOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999).getTime();

    const todayKey = key(now);
    const y = new Date(now); y.setDate(now.getDate() - 1);
    const yKey = key(y);

    let tTotal = 0; let yTotal = 0;
    const tDoses: { mg: number; source?: string; ts: number }[] = [];
    for (const d of doses) {
      const dt = new Date(d.timestamp);
      const k = key(dt);
      if (k === todayKey) { tTotal += d.mg; tDoses.push({ mg: d.mg, source: d.source, ts: d.timestamp }); }
      else if (k === yKey) { yTotal += d.mg; }
    }
    tDoses.sort((a, b) => b.ts - a.ts);
    const delta = tTotal - yTotal;
    const deltaText = `${delta >= 0 ? '+' : ''}${delta} vs yesterday`;
    return { todayTotal: tTotal, yesterdayTotal: yTotal, deltaText, todayDoses: tDoses };
  }, [doses]);

  const addDoseQuick = (mg: number) => {
    const id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    addDose({ id, timestamp: Date.now(), mg });
  };

  const openCustom = () => {
    // TODO: navigate to custom add screen
  };

  // Derive a simple 1-word energy descriptor from the alertness score
  const energyWord = useMemo(() => {
    const s = Math.round(nowScore ?? 0);
    if (s >= 67) return 'High';
    if (s >= 34) return 'Medium';
    return 'Low';
  }, [nowScore]);

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      showsVerticalScrollIndicator={false}
      contentContainerStyle={{ paddingTop: 12, paddingBottom: 24, paddingHorizontal: 16, alignItems: 'center' }}
    >
      <View style={{ width: '100%', maxWidth: CONTENT_MAX_WIDTH, gap: 16 }}>
        {/* Hero card */}
        <Panel>
          <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel'), marginBottom: 6 }}>
            Today’s caffeine
          </Text>
          <View style={{ flexDirection: 'row', alignItems: 'flex-end', gap: 8 }}>
            <Text style={{ fontSize: 34, lineHeight: 41, fontWeight: '600', color: PlatformColor('label') }}>
              {Math.round(todayTotal)}
            </Text>
            <Text style={{ fontSize: 22, lineHeight: 28, color: PlatformColor('secondaryLabel') }}>mg</Text>
            <View style={{ flex: 1 }} />
            <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>
              {fmtTime(cutoff?.nextCutoff)}
            </Text>
          </View>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 6 }}>
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>{deltaText}</Text>
          </View>
        </Panel>

        {/* Secondary metrics */}
        <View style={{ flexDirection: 'row', gap: 12 }}>
          <MetricTile title="Alertness" value={`${Math.round(nowScore ?? 0)} ${energyWord}`} />
          <MetricTile title="Cutoff" value={fmtTime(cutoff?.nextBedtime)} />
        </View>

        {/* Quick add */}
        <View>
          <SectionHeader title="Quick Add" />
          <QuickAddGrid onAdd={addDoseQuick} onCustom={openCustom} />
        </View>

        {/* Timeline */}
        <View>
          <SectionHeader title="Today" />
          <Panel style={{ paddingVertical: 8 }}>
            {todayDoses.length === 0 ? (
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
                No doses yet. Add your first dose.
              </Text>
            ) : (
              todayDoses.map((d, idx) => (
                <View key={d.ts} style={{ borderTopWidth: idx === 0 ? 0 : 1, borderColor: PlatformColor('separator') }}>
                  <TimelineItem
                    amount={`${d.mg} mg`}
                    source={d.source}
                    time={fmtTime(d.ts)}
                  />
                </View>
              ))
            )}
            <Pressable
              onPress={() => {}}
              accessibilityRole="button"
              style={{ alignSelf: 'center', paddingVertical: 8, paddingHorizontal: 12, minHeight: HIT_TARGET }}
            >
              <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('tint') }}>View all →</Text>
            </Pressable>
          </Panel>
        </View>

        {/* Insights */}
        <View>
          <SectionHeader title="Insights" />
          <Panel>
            <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>
              Best window for focus: 10:00–12:00
            </Text>
            <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel'), marginTop: 4 }}>
              Based on your recent intake and sleep.
            </Text>
          </Panel>
        </View>

        {/* Warning after cutoff */}
        {cutoff?.shouldWarn ? (
          <Panel>
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('systemRed'), textAlign: 'center' }}>
              Caffeine past cutoff may impact sleep
            </Text>
          </Panel>
        ) : null}
      </View>
    </ScrollView>
  );
}

// Optional helper for trend
function computeTrend(series: any[] | undefined) {
  if (!series || series.length < 2) return 0;
  const a = series[series.length - 2]?.score ?? 0;
  const b = series[series.length - 1]?.score ?? 0;
  return Math.sign(b - a);
}
