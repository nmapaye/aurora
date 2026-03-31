import React, { useMemo } from 'react';
import { View, Text, Pressable, useColorScheme, PlatformColor } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useStore } from '~/state/store';
import { useAlertnessSeries } from '~/hooks/useAlertnessSeries';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';
import useSleepGuidance from '~/hooks/useSleepGuidance';
import ScreenContainer from '~/components/ScreenContainer';
import { navigate } from '~/navigation';
import CaffeineTodayGraph from '~/components/CaffeineTodayGraph';
import { getPrimaryButtonColors } from '~/theme/colors';

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
  const scheme = useColorScheme();
  const glassBg = scheme === 'dark' ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.7)';
  const glassBorder = scheme === 'dark' ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.2)';
  return (
    <View
      style={[
        {
          backgroundColor: glassBg,
          borderRadius: 18,
          padding: 16,
          borderWidth: 1,
          borderColor: glassBorder,
          shadowColor: '#000',
          shadowOpacity: 0.12,
          shadowRadius: 12,
          shadowOffset: { width: 0, height: 6 },
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

function MetricTile({ title, value, right }: { title: string; value: string; right?: React.ReactNode }) {
  const scheme = useColorScheme();
  const bg = scheme === 'dark' ? 'rgba(255,255,255,0.04)' : 'rgba(255,255,255,0.9)';
  return (
    <View
      style={{
        flex: 1,
        minHeight: HIT_TARGET,
        padding: 12,
        borderRadius: 14,
        backgroundColor: bg,
        borderWidth: 0,
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

function QuickAddGrid({ onAdd }: { onAdd: (mg: number, source?: string) => void }) {
  const drinks: { label: string; mg: number }[] = [
    { label: 'Soda', mg: 40 },
    { label: 'Espresso', mg: 60 },
    { label: 'Matcha', mg: 70 },
    { label: 'Drip Coffee', mg: 95 },
    { label: 'Energy Drink', mg: 160 },
  ];
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 12 }}>
      {drinks.map((d) => (
        <Pressable
          key={d.label}
          onPress={() => onAdd(d.mg, d.label)}
          accessibilityRole="button"
          accessibilityLabel={`Add ${d.label}`}
          hitSlop={12}
          style={{
            minHeight: HIT_TARGET,
            minWidth: 96,
            paddingHorizontal: 18,
            paddingVertical: 10,
            borderRadius: 999,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: PlatformColor('systemFill'),
            borderWidth: 0,
          }}
        >
          <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>{d.label}</Text>
        </Pressable>
      ))}
    </View>
  );
}

function TimelineItem({ amount, source, time, right }: { amount: string; source?: string; time: string; right?: React.ReactNode }) {
  const label = `${amount}${source ? ` ${source}` : ''} at ${time}`;
  return (
    <View
      accessible
      accessibilityRole="summary"
      accessibilityLabel={label}
      style={{ paddingVertical: 10, minHeight: HIT_TARGET }}
    >
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>{amount}</Text>
          <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
            {source ? `${source} • ${time}` : time}
          </Text>
        </View>
        {right}
      </View>
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
  const primaryButton = getPrimaryButtonColors(scheme);
  const { nowScore, mgActiveNow: mgActive } = (useAlertnessSeries() as any) || {};
  const cutoff = useCaffeineCutoff();
  const sleepGuidance = useSleepGuidance();

  const doses = useStore((s) => s.doses);
  const latestVigilanceSession = useStore((s) => s.vigilanceSessions[0]);
  const addDose = useStore((s) => s.addDose);
  const removeDose = useStore((s) => (s as any).removeDose);

  const { todayTotal, deltaText, todayDoses } = useMemo(() => {
    const now = new Date();
    const key = (d: Date) => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
    const todayKey = key(now);
    const y = new Date(now); y.setDate(now.getDate() - 1);
    const yKey = key(y);

    let tTotal = 0; let yTotal = 0;
    const tDoses: { id?: string; mg: number; source?: string; ts: number }[] = [];
    for (const d of doses) {
      const dt = new Date(d.timestamp);
      const k = key(dt);
      if (k === todayKey) { tTotal += d.mg; tDoses.push({ id: (d as any).id, mg: d.mg, source: d.source, ts: d.timestamp }); }
      else if (k === yKey) { yTotal += d.mg; }
    }
    tDoses.sort((a, b) => b.ts - a.ts);
    const delta = tTotal - yTotal;
    const deltaText = `${delta >= 0 ? '+' : ''}${delta} vs yesterday`;
    return { todayTotal: tTotal, deltaText, todayDoses: tDoses };
  }, [doses]);

  const addDoseQuick = (mg: number, source?: string) => {
    const id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    addDose({ id, timestamp: Date.now(), mg, source });
  };

  const openCustom = () => {
    navigate('Log');
  };

  // Derive a simple 1-word energy descriptor from the alertness score
  const energyWord = useMemo(() => {
    const s = Math.round(nowScore ?? 0);
    if (s >= 67) return 'High';
    if (s >= 34) return 'Medium';
    return 'Low';
  }, [nowScore]);

  const gradient: readonly [string, string, string] =
    scheme === 'dark'
      ? ['#0b0f1c', '#0e1c2c', '#0c2536']
      : ['#f9f7ff', '#f0f6ff', '#e5f7f9'];

  const latestVigilanceLabel = latestVigilanceSession
    ? `${latestVigilanceSession.score} ${latestVigilanceSession.rating}`
    : 'No baseline yet';

  return (
    <View style={{ flex: 1 }}>
      <LinearGradient colors={gradient} style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} />
      <ScreenContainer center contentStyle={{ paddingTop: 20, paddingBottom: 40 }}>
        <View style={{ width: '100%', maxWidth: CONTENT_MAX_WIDTH, gap: 16 }}>
          {/* Hero card */}
          <Panel style={{ padding: 18 }}>
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel'), marginBottom: 8 }}>
              Today’s caffeine
            </Text>
            <View style={{ flexDirection: 'row', alignItems: 'flex-end', gap: 8 }}>
              <View>
                <Text style={{ fontSize: 42, lineHeight: 48, fontWeight: '700', color: PlatformColor('label') }}>
                  {Math.round(todayTotal)}
                </Text>
                <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel'), marginTop: 2 }}>{deltaText}</Text>
              </View>
              <Text style={{ fontSize: 20, lineHeight: 24, color: PlatformColor('secondaryLabel') }}>mg</Text>
              <View style={{ flex: 1 }} />
              <View style={{ alignItems: 'flex-end' }}>
                <Text style={{ fontSize: 14, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>Cutoff</Text>
                <Text style={{ fontSize: 18, lineHeight: 22, fontWeight: '600', color: PlatformColor('label') }}>
                  {fmtTime(cutoff?.nextCutoff)}
                </Text>
              </View>
            </View>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: 12 }}>
              <View style={{ paddingHorizontal: 12, paddingVertical: 8, borderRadius: 999, backgroundColor: PlatformColor('systemFill') }}>
                <Text style={{ color: PlatformColor('label'), fontSize: 13, lineHeight: 18 }}>Active: {Math.round(mgActive)} mg</Text>
              </View>
              <View style={{ paddingHorizontal: 12, paddingVertical: 8, borderRadius: 999, backgroundColor: PlatformColor('systemFill') }}>
                <Text style={{ color: PlatformColor('label'), fontSize: 13, lineHeight: 18 }}>Energy: {energyWord}</Text>
              </View>
            </View>
          </Panel>

        {/* Secondary metrics */}
        <View style={{ flexDirection: 'row', gap: 12 }}>
          <MetricTile title="Alertness" value={`${Math.round(nowScore ?? 0)} ${energyWord}`} />
          <MetricTile
            title="Bedtime"
            value={fmtTime(sleepGuidance?.bedtime)}
            right={
              <Pressable
                onPress={() => navigate('Insights')}
                accessibilityRole="button"
                accessibilityLabel="Why bedtime?"
                hitSlop={8}
                style={{ paddingHorizontal: 10, paddingVertical: 6, borderRadius: 999, backgroundColor: PlatformColor('systemFill'), borderWidth: 0 }}
              >
                <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('label') }}>Why?</Text>
              </Pressable>
            }
          />
        </View>

        {/* Today caffeine level graph */}
        <Panel>
          <CaffeineTodayGraph />
        </Panel>

        {/* Vigilance test */}
        <View>
          <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 6 }}>
            <SectionHeader title="Vigilance Test" />
            <View style={{ flex: 1 }} />
            <Pressable
              onPress={() => navigate('VigilanceTest')}
              accessibilityRole="button"
              accessibilityLabel="Start vigilance test"
              hitSlop={12}
              style={{
                minHeight: 36,
                paddingHorizontal: 14,
                borderRadius: 999,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: primaryButton.backgroundColor,
              }}
            >
              <Text style={{ fontSize: 15, lineHeight: 20, color: primaryButton.color, fontWeight: '600' }}>
                Start
              </Text>
            </Pressable>
          </View>
          <Panel>
            <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>
              Measure attentiveness with a 60-second reaction task.
            </Text>
            <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel'), marginTop: 4 }}>
              Keep this separate from caffeine guidance and use it to build a repeatable focus baseline.
            </Text>
            <View style={{ flexDirection: 'row', gap: 12, marginTop: 12 }}>
              <MetricTile title="Latest" value={latestVigilanceLabel} />
              <MetricTile
                title="Median Reaction"
                value={
                  latestVigilanceSession?.medianReactionMs
                    ? `${latestVigilanceSession.medianReactionMs} ms`
                    : '—'
                }
              />
            </View>
          </Panel>
        </View>

        {/* Quick add */}
        <View>
          <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 6 }}>
            <SectionHeader title="Quick Add" />
            <View style={{ flex: 1 }} />
            <Pressable
              onPress={openCustom}
              accessibilityRole="button"
              accessibilityLabel="Custom add"
              hitSlop={12}
              style={{
                minHeight: 36,
                paddingHorizontal: 14,
                borderRadius: 999,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: PlatformColor('tintColor'),
              }}
            >
              <Text style={{ fontSize: 15, lineHeight: 20, color: '#FFFFFF', fontWeight: '600' }}>Custom</Text>
            </Pressable>
          </View>
          <QuickAddGrid onAdd={addDoseQuick} />
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
                <View key={d.id ?? `${d.ts}-${idx}`} style={{ borderTopWidth: idx === 0 ? 0 : 1, borderColor: PlatformColor('separator') }}>
                  <TimelineItem
                    amount={`${d.mg} mg`}
                    source={d.source}
                    time={fmtTime(d.ts)}
                    right={
                      <Pressable
                        onPress={() => { if (d.id) removeDose?.(d.id); }}
                        accessibilityRole="button"
                        accessibilityLabel="Delete dose"
                        hitSlop={12}
                        style={{ minHeight: 32, paddingHorizontal: 10, borderRadius: 8, alignItems: 'center', justifyContent: 'center', backgroundColor: PlatformColor('systemFill'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                      >
                        <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('label') }}>Delete</Text>
                      </Pressable>
                    }
                  />
                </View>
              ))
            )}
            <Pressable
              onPress={() => navigate('History')}
              accessibilityRole="button"
              style={{ alignSelf: 'center', paddingVertical: 8, paddingHorizontal: 12, minHeight: HIT_TARGET }}
            >
              <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('tintColor') }}>View all →</Text>
            </Pressable>
          </Panel>
        </View>

        {/* Quick Insights */}
        <View>
          <SectionHeader title="Quick Insights" />
          <Panel>
            <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>
              Best consumption window for focus: 10:00–12:00
            </Text>
            <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel'), marginTop: 4 }}>
              Based on recent intake and sleep patterns.
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
    </ScreenContainer>
    </View>
  );
}
