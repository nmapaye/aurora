import React, { useMemo, useState } from 'react';
import { Share, Text, View, useColorScheme } from 'react-native';

import Button from '~/components/Button';
import { FieldInput, SectionCard, SectionTitle, SegmentedControl } from '~/components/ui';
import { makeVigilanceSessionsCSV } from '~/services/storage/export';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';

type RangeKey = '7' | '14' | '30' | 'all';
type HistorySection = 'doses' | 'vigilance';

type Props = {
  initialSection?: HistorySection;
};

export default function HistoryContent({ initialSection = 'doses' }: Props) {
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const doses = useStore((state) => state.doses);
  const vigilanceSessions = useStore((state) => state.vigilanceSessions);
  const updateDose = useStore((state) => state.updateDose);
  const removeDose = useStore((state) => state.removeDose);

  const [section, setSection] = useState<HistorySection>(initialSection);
  const [range, setRange] = useState<RangeKey>('14');
  const [query, setQuery] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draftMg, setDraftMg] = useState('0');
  const [draftSource, setDraftSource] = useState('');

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

  const saveEdit = () => {
    if (!editingId) return;
    updateDose(editingId, {
      mg: Math.max(1, Math.round(Number(draftMg) || 0)),
      source: draftSource.trim() || undefined,
    });
    setEditingId(null);
  };

  return (
    <View style={{ gap: 16 }}>
      <SectionTitle action={<Button title="Export CSV" variant="secondary" onPress={exportCurrentSection} />}>
        History
      </SectionTitle>

      <SegmentedControl
        value={section}
        onChange={setSection}
        options={[
          { key: 'doses', label: 'Doses' },
          { key: 'vigilance', label: 'Vigilance' },
        ]}
      />

      {section === 'doses' ? (
        <>
          <SegmentedControl
            value={range}
            onChange={setRange}
            options={[
              { key: '7', label: '7d' },
              { key: '14', label: '14d' },
              { key: '30', label: '30d' },
              { key: 'all', label: 'All' },
            ]}
          />

          <FieldInput
            value={query}
            onChangeText={setQuery}
            placeholder="Search amount, source, or note"
          />

          <SectionCard>
            {doseItems.length === 0 ? (
              <Text
                style={{
                  fontSize: 15,
                  lineHeight: 20,
                  color: palette.textSecondary,
                }}
              >
                No doses logged in this range yet.
              </Text>
            ) : (
              doseItems.map((dose, index) => {
                const isEditing = editingId === dose.id;
                return (
                  <View
                    key={dose.id}
                    style={{
                      gap: 10,
                      paddingTop: index === 0 ? 0 : 14,
                      borderTopWidth: index === 0 ? 0 : 1,
                      borderColor: palette.separator,
                    }}
                  >
                    <View style={{ gap: 4 }}>
                      <Text
                        style={{
                          fontSize: 17,
                          lineHeight: 22,
                          fontWeight: '600',
                          color: palette.textPrimary,
                        }}
                      >
                        {dose.mg} mg{dose.source ? ` • ${dose.source}` : ''}
                      </Text>
                      <Text
                        style={{
                          fontSize: 13,
                          lineHeight: 18,
                          color: palette.textSecondary,
                        }}
                      >
                        {fmtDateTime(dose.timestamp)}
                      </Text>
                      {dose.note ? (
                        <Text
                          style={{
                            fontSize: 13,
                            lineHeight: 18,
                            color: palette.textTertiary,
                          }}
                        >
                          {dose.note}
                        </Text>
                      ) : null}
                    </View>

                    {isEditing ? (
                      <View style={{ gap: 10 }}>
                        <View style={{ flexDirection: 'row', gap: 10 }}>
                          <FieldInput
                            value={draftMg}
                            onChangeText={setDraftMg}
                            keyboardType="number-pad"
                            placeholder="mg"
                            style={{ flex: 1 }}
                          />
                          <FieldInput
                            value={draftSource}
                            onChangeText={setDraftSource}
                            placeholder="Source"
                            style={{ flex: 1.2 }}
                          />
                        </View>
                        <View style={{ flexDirection: 'row', gap: 10 }}>
                          <Button title="Save" onPress={saveEdit} />
                          <Button title="Cancel" variant="secondary" onPress={() => setEditingId(null)} />
                        </View>
                      </View>
                    ) : (
                      <View style={{ flexDirection: 'row', gap: 10 }}>
                        <Button
                          title="Edit"
                          variant="secondary"
                          onPress={() => {
                            setEditingId(dose.id);
                            setDraftMg(String(dose.mg));
                            setDraftSource(dose.source || '');
                          }}
                        />
                        <Button
                          title="Delete"
                          variant="plain"
                          onPress={() => removeDose(dose.id)}
                        />
                      </View>
                    )}
                  </View>
                );
              })
            )}
          </SectionCard>
        </>
      ) : (
        <SectionCard>
          {vigilanceSessions.length === 0 ? (
            <Text
              style={{
                fontSize: 15,
                lineHeight: 20,
                color: palette.textSecondary,
              }}
            >
              No vigilance sessions yet. Run the reaction test from Home to start building a baseline.
            </Text>
          ) : (
            vigilanceSessions.map((session, index) => (
              <View
                key={session.id}
                style={{
                  gap: 6,
                  paddingTop: index === 0 ? 0 : 14,
                  borderTopWidth: index === 0 ? 0 : 1,
                  borderColor: palette.separator,
                }}
              >
                <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 12 }}>
                  <View style={{ flex: 1, gap: 4 }}>
                    <Text
                      style={{
                        fontSize: 17,
                        lineHeight: 22,
                        fontWeight: '600',
                        color: palette.textPrimary,
                      }}
                    >
                      {session.score} {session.rating}
                    </Text>
                    <Text
                      style={{
                        fontSize: 13,
                        lineHeight: 18,
                        color: palette.textSecondary,
                      }}
                    >
                      {fmtDateTime(session.completedAt)}
                    </Text>
                    <Text
                      style={{
                        fontSize: 13,
                        lineHeight: 18,
                        color: palette.textTertiary,
                      }}
                    >
                      Median {session.medianReactionMs ?? '—'} ms • Lapses {session.lapseCount} • False starts {session.falseStartCount}
                    </Text>
                  </View>
                  <View
                    style={{
                      minWidth: 88,
                      paddingHorizontal: 12,
                      paddingVertical: 10,
                      borderRadius: 14,
                      backgroundColor: palette.cardMuted,
                      borderWidth: 1,
                      borderColor: palette.cardBorder,
                      alignItems: 'center',
                    }}
                  >
                    <Text
                      style={{
                        fontSize: 15,
                        lineHeight: 20,
                        fontWeight: '700',
                        color: palette.textPrimary,
                      }}
                    >
                      {session.validReactionCount}/{session.trialCount}
                    </Text>
                    <Text
                      style={{
                        fontSize: 12,
                        lineHeight: 16,
                        color: palette.textSecondary,
                      }}
                    >
                      valid taps
                    </Text>
                  </View>
                </View>
              </View>
            ))
          )}
        </SectionCard>
      )}
    </View>
  );
}
