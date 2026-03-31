import React, { useMemo, useState } from 'react';
import {
  View,
  Text,
  Pressable,
  TextInput,
  PlatformColor,
  Share,
  useColorScheme,
} from 'react-native';

import ScreenContainer from '~/components/ScreenContainer';
import { useStore } from '~/state/store';
import { getPrimaryButtonColors } from '~/theme/colors';
import { makeVigilanceSessionsCSV } from '~/services/storage/export';

const HIT_TARGET = 44;

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

type RangeKey = '7' | '14' | '30' | 'all';
type HistorySection = 'doses' | 'vigilance';

export default function HistoryScreen() {
  const scheme = useColorScheme();
  const primaryButton = getPrimaryButtonColors(scheme);
  const doses = useStore((s) => s.doses);
  const vigilanceSessions = useStore((s) => s.vigilanceSessions);
  const updateDose = useStore(
    (s) => (s as any).updateDose as (id: string, patch: any) => void
  );
  const removeDose = useStore((s) => (s as any).removeDose as (id: string) => void);

  const [section, setSection] = useState<HistorySection>('doses');
  const [range, setRange] = useState<RangeKey>('7');
  const [query, setQuery] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draftMg, setDraftMg] = useState<number>(0);
  const [draftSource, setDraftSource] = useState<string>('');

  const rangeStart = useMemo(() => {
    if (range === 'all') return 0;
    const days = range === '7' ? 7 : range === '14' ? 14 : 30;
    const date = new Date();
    date.setHours(23, 59, 59, 999);
    return date.getTime() - days * 24 * 3600 * 1000;
  }, [range]);

  const doseItems = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();
    return [...doses]
      .filter((dose) => dose.timestamp >= rangeStart)
      .filter((dose) =>
        normalizedQuery
          ? `${dose.mg}`.includes(normalizedQuery) ||
            (dose.source || '').toLowerCase().includes(normalizedQuery) ||
            (dose.note || '').toLowerCase().includes(normalizedQuery)
          : true
      )
      .sort((a, b) => b.timestamp - a.timestamp);
  }, [doses, query, rangeStart]);

  const fmtDateTime = (timestamp: number) => {
    try {
      return new Intl.DateTimeFormat(undefined, {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      }).format(new Date(timestamp));
    } catch {
      return new Date(timestamp).toLocaleString();
    }
  };

  const saveEdit = () => {
    if (!editingId) return;
    updateDose(editingId, {
      mg: Math.max(1, Math.round(draftMg)),
      source: draftSource || undefined,
    });
    setEditingId(null);
  };

  const exportCurrentSection = async () => {
    if (section === 'doses') {
      const header = 'id,timestamp,datetime,mg,source,note';
      const lines = doseItems.map((dose) => {
        const iso = new Date(dose.timestamp).toISOString();
        return [dose.id, String(dose.timestamp), iso, String(dose.mg), dose.source || '', dose.note || '']
          .map((value) => `"${String(value).replace(/"/g, '""')}"`)
          .join(',');
      });
      await Share.share({ message: [header, ...lines].join('\n') });
      return;
    }
    await Share.share({ message: makeVigilanceSessionsCSV(vigilanceSessions) });
  };

  return (
    <ScreenContainer>
      <View style={{ width: '100%', maxWidth: 560, gap: 16 }}>
        <Panel>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 12 }}>
            {([
              ['doses', 'Doses'],
              ['vigilance', 'Vigilance'],
            ] as const).map(([key, label]) => {
              const active = section === key;
              return (
                <Pressable
                  key={key}
                  onPress={() => setSection(key)}
                  accessibilityRole="button"
                  accessibilityState={{ selected: active }}
                  style={{
                    minHeight: HIT_TARGET,
                    paddingHorizontal: 14,
                    borderRadius: 999,
                    alignItems: 'center',
                    justifyContent: 'center',
                    backgroundColor: active
                      ? PlatformColor('systemFill')
                      : PlatformColor('tertiarySystemBackground'),
                    borderWidth: 1,
                    borderColor: PlatformColor('separator'),
                  }}
                >
                  <Text style={{ color: PlatformColor('label'), fontWeight: active ? '600' : '400' }}>
                    {label}
                  </Text>
                </Pressable>
              );
            })}
            <View style={{ flex: 1 }} />
            <Pressable
              onPress={exportCurrentSection}
              accessibilityRole="button"
              style={{
                minHeight: HIT_TARGET,
                paddingHorizontal: 12,
                borderRadius: 12,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: primaryButton.backgroundColor,
              }}
            >
              <Text style={{ color: primaryButton.color, fontWeight: '600' }}>
                Export CSV
              </Text>
            </Pressable>
          </View>

          {section === 'doses' ? (
            <>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 8 }}>
                {(['7', '14', '30', 'all'] as RangeKey[]).map((key) => {
                  const active = range === key;
                  const label = key === 'all' ? 'All' : `${key}d`;
                  return (
                    <Pressable
                      key={key}
                      onPress={() => setRange(key)}
                      accessibilityRole="button"
                      accessibilityState={{ selected: active }}
                      style={{
                        paddingHorizontal: 12,
                        paddingVertical: 8,
                        borderRadius: 999,
                        backgroundColor: active
                          ? PlatformColor('systemFill')
                          : PlatformColor('tertiarySystemBackground'),
                        borderWidth: 1,
                        borderColor: PlatformColor('separator'),
                      }}
                    >
                      <Text style={{ color: PlatformColor('label') }}>{label}</Text>
                    </Pressable>
                  );
                })}
              </View>

              <TextInput
                placeholder="Search (amount, source, note)"
                placeholderTextColor={PlatformColor('tertiaryLabel')}
                value={query}
                onChangeText={setQuery}
                style={{
                  minHeight: 40,
                  borderRadius: 10,
                  paddingHorizontal: 12,
                  paddingVertical: 8,
                  backgroundColor: PlatformColor('tertiarySystemBackground'),
                  borderWidth: 1,
                  borderColor: PlatformColor('separator'),
                  color: PlatformColor('label'),
                  marginBottom: 8,
                }}
              />

              {doseItems.length === 0 ? (
                <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
                  No doses logged yet.
                </Text>
              ) : (
                doseItems.map((dose, idx) => (
                  <View
                    key={dose.id}
                    style={{
                      paddingVertical: 10,
                      borderTopWidth: idx === 0 ? 0 : 1,
                      borderColor: PlatformColor('separator'),
                    }}
                  >
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
                      <View style={{ flex: 1 }}>
                        <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>
                          {dose.mg} mg {dose.source ? `• ${dose.source}` : ''}
                        </Text>
                        <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
                          {fmtDateTime(dose.timestamp)}
                        </Text>
                      </View>
                      {editingId === dose.id ? (
                        <>
                          <TextInput
                            value={String(draftMg)}
                            onChangeText={(text) => setDraftMg(parseInt(text || '0', 10))}
                            keyboardType="number-pad"
                            style={{
                              minWidth: 64,
                              textAlign: 'center',
                              borderBottomWidth: 1,
                              borderColor: PlatformColor('separator'),
                              color: PlatformColor('label'),
                            }}
                          />
                          <TextInput
                            value={draftSource}
                            onChangeText={setDraftSource}
                            placeholder="Source"
                            placeholderTextColor={PlatformColor('tertiaryLabel')}
                            style={{
                              minWidth: 96,
                              textAlign: 'left',
                              borderBottomWidth: 1,
                              borderColor: PlatformColor('separator'),
                              color: PlatformColor('label'),
                            }}
                          />
                          <Pressable
                            onPress={saveEdit}
                            accessibilityRole="button"
                            style={{
                              minHeight: HIT_TARGET,
                              paddingHorizontal: 12,
                              borderRadius: 10,
                              backgroundColor: primaryButton.backgroundColor,
                              alignItems: 'center',
                              justifyContent: 'center',
                            }}
                          >
                            <Text style={{ color: primaryButton.color, fontWeight: '600' }}>Save</Text>
                          </Pressable>
                          <Pressable
                            onPress={() => setEditingId(null)}
                            accessibilityRole="button"
                            style={{
                              minHeight: HIT_TARGET,
                              paddingHorizontal: 12,
                              borderRadius: 10,
                              backgroundColor: PlatformColor('systemFill'),
                              alignItems: 'center',
                              justifyContent: 'center',
                            }}
                          >
                            <Text style={{ color: PlatformColor('label') }}>Cancel</Text>
                          </Pressable>
                        </>
                      ) : (
                        <>
                          <Pressable
                            onPress={() => {
                              setEditingId(dose.id);
                              setDraftMg(dose.mg);
                              setDraftSource(dose.source || '');
                            }}
                            accessibilityRole="button"
                            style={{
                              minHeight: HIT_TARGET,
                              paddingHorizontal: 12,
                              borderRadius: 10,
                              backgroundColor: PlatformColor('systemFill'),
                              alignItems: 'center',
                              justifyContent: 'center',
                            }}
                          >
                            <Text style={{ color: PlatformColor('label') }}>Edit</Text>
                          </Pressable>
                          <Pressable
                            onPress={() => removeDose(dose.id)}
                            accessibilityRole="button"
                            style={{
                              minHeight: HIT_TARGET,
                              paddingHorizontal: 12,
                              borderRadius: 10,
                              backgroundColor: PlatformColor('systemFill'),
                              alignItems: 'center',
                              justifyContent: 'center',
                            }}
                          >
                            <Text style={{ color: PlatformColor('label') }}>Delete</Text>
                          </Pressable>
                        </>
                      )}
                    </View>
                  </View>
                ))
              )}
            </>
          ) : vigilanceSessions.length === 0 ? (
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
              No vigilance sessions yet. Run the dashboard reaction test to start tracking attentiveness.
            </Text>
          ) : (
            vigilanceSessions.map((session, idx) => (
              <View
                key={session.id}
                style={{
                  paddingVertical: 12,
                  borderTopWidth: idx === 0 ? 0 : 1,
                  borderColor: PlatformColor('separator'),
                }}
              >
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>
                      {session.score} {session.rating}
                    </Text>
                    <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
                      {fmtDateTime(session.completedAt)}
                    </Text>
                    <Text style={{ marginTop: 4, fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>
                      Median {session.medianReactionMs ?? '—'} ms • Lapses {session.lapseCount} • False starts {session.falseStartCount}
                    </Text>
                  </View>
                  <View
                    style={{
                      minHeight: HIT_TARGET,
                      minWidth: 88,
                      paddingHorizontal: 12,
                      borderRadius: 10,
                      backgroundColor: PlatformColor('systemFill'),
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}
                  >
                    <Text style={{ color: PlatformColor('label'), fontWeight: '600' }}>
                      {session.validReactionCount}/{session.trialCount}
                    </Text>
                    <Text style={{ fontSize: 12, lineHeight: 16, color: PlatformColor('secondaryLabel') }}>
                      valid
                    </Text>
                  </View>
                </View>
              </View>
            ))
          )}
        </Panel>
      </View>
    </ScreenContainer>
  );
}
