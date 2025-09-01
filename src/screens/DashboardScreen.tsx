import React from 'react';
import { ScrollView, View, Text, Pressable, useColorScheme } from 'react-native';
import Card from '~/components/Card';
import DoseQuickButtons from '~/components/DoseQuickButtons';
import MgActiveBadge from '~/components/MgActiveBadge';
import SleepSessionItem from '~/components/SleepSessionItem';
import { useAlertnessSeries } from '~/hooks/useAlertnessSeries';
import useNextDip from '~/hooks/useNextDip';
import * as cutoffHook from '~/hooks/useCaffeineCutoff';

const CONTENT_MAX_WIDTH = 560;

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
  const { nowScore, mgActiveNow: mgActive, series } = (useAlertnessSeries() as any) || {};

  // useNextDip export can be default or not; guard the call
  const _useNextDip: any = (useNextDip as any);
  const nextDip: number | undefined = typeof _useNextDip === 'function' ? _useNextDip() : undefined;

  // useCaffeineCutoff may export a hook or a function; guard
  const cutoffResult: any = (cutoffHook as any)?.useCaffeineCutoff
    ? (cutoffHook as any).useCaffeineCutoff()
    : typeof (cutoffHook as any) === 'function'
    ? (cutoffHook as any)()
    : undefined;
  const cutoff: number | undefined = cutoffResult?.cutoff;

  const scheme = useColorScheme();
  const buttonTextColor = scheme === 'dark' ? '#ffffff' : '#0a0a0a';
  const buttonBorderColor = scheme === 'dark' ? '#4a4a4a' : '#cccccc';

  return (
    <ScrollView
      contentContainerStyle={{
        paddingTop: 16,
        paddingBottom: 24,
        paddingHorizontal: 16,
        alignItems: 'center',
      }}
    >
      <View style={{ width: '100%', maxWidth: CONTENT_MAX_WIDTH, gap: 12 }}>
        {/* 1) Status strip */}
        <Card>
          <View style={{ alignItems: 'center', gap: 8 }}>
            <MgActiveBadge />
            <Text>
              Next dip: {fmtTime(nextDip)} • Cutoff: {fmtTime(cutoff)}
            </Text>
          </View>
        </Card>

        {/* 2) Primary gauge */}
        <Card>
          <View style={{ alignItems: 'center', gap: 12 }}>
            {/* <AlertnessRing value={nowScore ?? 0} trend={computeTrend(series)} /> */}
            <Text style={{ fontSize: 18, fontWeight: '600' }}>Alertness now: {Math.round(nowScore ?? 0)}</Text>
          </View>
        </Card>

        {/* 3) Projection graph */}
        <Card>
          <View style={{ alignItems: 'center' }}>
            {/* <TimelineGraph series={series ?? []} markers={{ now: Date.now(), nextDip, cutoff }} /> */}
            <Text>Projection: 12-hour timeline</Text>
          </View>
        </Card>

        {/* 4) Quick actions */}
        <Card>
          <View style={{ alignItems: 'center' }}>
            <DoseQuickButtons />
            <View style={{ height: 13 }} />
            <View style={{ flexDirection: 'row', gap: 12 }}>
              <Pressable style={{ paddingHorizontal: 14, paddingVertical: 10, borderRadius: 12, borderWidth: 1, borderColor: buttonBorderColor }}>
                <Text style={{ color: buttonTextColor }}>Custom dose…</Text>
              </Pressable>
              <Pressable style={{ paddingHorizontal: 14, paddingVertical: 10, borderRadius: 12, borderWidth: 1, borderColor: buttonBorderColor }}>
                <Text style={{ color: buttonTextColor }}>Start nap</Text>
              </Pressable>
              <Pressable style={{ paddingHorizontal: 14, paddingVertical: 10, borderRadius: 12, borderWidth: 1, borderColor: buttonBorderColor }}>
                <Text style={{ color: buttonTextColor }}>Start sleep</Text>
              </Pressable>
            </View>
          </View>
        </Card>

        {/* 5) Recent activity */}
        <Card>
          <View style={{ gap: 10 }}>
            <Text style={{ fontWeight: '600', textAlign: 'center' }}>Recent activity</Text>
            {/* Replace placeholders with real rows from store */}
            <View style={{ opacity: 0.7 }}>
              <Text>45 mg • Espresso • 14:05</Text>
            </View>
            <SleepSessionItem
              // @ts-ignore placeholder props; replace with real session data
              session={{ id: 'demo', start: new Date().toISOString(), end: new Date().toISOString(), kind: 'nap' }}
            />
            <Pressable style={{ alignSelf: 'center', paddingVertical: 6, paddingHorizontal: 8 }}>
              <Text>View all →</Text>
            </Pressable>
          </View>
        </Card>

        {/* 6) Daily budget */}
        <Card>
          <View style={{ alignItems: 'center', gap: 6 }}>
            <Text style={{ fontWeight: '600' }}>Daily budget</Text>
            <Text>{Math.round(mgActive ?? 0)} mg active • 200 mg budget</Text>
            <View style={{ height: 8, width: '100%', backgroundColor: '#eee', borderRadius: 999 }}>
              <View
                style={{
                  height: 8,
                  width: `${Math.min(100, Math.round(((mgActive ?? 0) / 200) * 100))}%`,
                  backgroundColor: '#0a84ff',
                  borderRadius: 999,
                }}
              />
            </View>
          </View>
        </Card>

        {/* 7) Warnings */}
        {cutoff && cutoff < Date.now() ? (
          <Card>
            <Text style={{ color: '#b00020', textAlign: 'center' }}>Caffeine past cutoff</Text>
          </Card>
        ) : null}

        {/* 8) First-run tips */}
        {!series?.length ? (
          <>
            <Card>
              <Text style={{ textAlign: 'center' }}>Log your first dose to unlock projections.</Text>
            </Card>
          </>
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