import React from 'react';
import { ScrollView, View, Text } from 'react-native';
import Card from '~/components/Card';
import { useAlertnessSeries } from '~/hooks/useAlertnessSeries';
import useNextDip from '~/hooks/useNextDip';

const CONTENT_MAX_WIDTH = 560; // keep in sync with other screens for consistent width

export default function InsightsScreen() {
  const { nowScore, mgActiveNow: mgActive, series } = useAlertnessSeries();
  const _useNextDip: any = (useNextDip as any);
  const nextDip = typeof _useNextDip === 'function' ? _useNextDip() : undefined;
  const hasData = Array.isArray(series) && series.length > 0;

  return (
    <ScrollView
      contentContainerStyle={{
        paddingTop: 16,
        paddingBottom: 24,
        paddingHorizontal: 16,
        alignItems: 'center',
      }}
    >
      <View style={{ width: '100%', maxWidth: CONTENT_MAX_WIDTH }}>
        {!hasData ? (
          <Card>
            <Text style={{ fontSize: 16, textAlign: 'center' }}>
              No data yet. Log a dose or a sleep session to generate insights.
            </Text>
          </Card>
        ) : (
          <>
            <Card>
              <View style={{ alignItems: 'center' }}>
                <Text style={{ fontSize: 18, fontWeight: '600' }}>Snapshot</Text>
                <Text style={{ marginTop: 8 }}>Active caffeine: {Math.round(mgActive)} mg</Text>
                <Text>Alertness now: {Math.round(nowScore)}</Text>
                {nextDip ? (
                  <Text>
                    Next dip: {new Date(nextDip as any).toLocaleTimeString()}
                  </Text>
                ) : null}
              </View>
            </Card>
          </>
        )}
      </View>
    </ScrollView>
  );
}
