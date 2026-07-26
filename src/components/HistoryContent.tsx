import React, { useMemo, useState } from 'react';
import { Share, Text, View } from 'react-native';

import Button from '~/components/Button';
import {
  FieldInput,
  SectionHeader,
  SectionCard,
  SegmentedControl,
} from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
import { makeVigilanceSessionsCSV } from '~/services/storage/export';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { radii, spacing, typeRamp } from '~/theme/tokens';

type RangeKey = '7' | '14' | '30' | 'all';
type HistorySection = 'doses' | 'vigilance';

type Props = {
  initialSection?: HistorySection;
  focused?: boolean;
};

export default function HistoryContent({ initialSection = 'doses', focused = false }: Props) {
  const scheme = useAppScheme();
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
          : true,
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
        return [
          dose.id,
          String(dose.timestamp),
          iso,
          String(dose.mg),
          dose.source || '',
          dose.note || '',
        ]
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
    <View style={{ gap: spacing.md }}>
      <SectionHeader
        prominence="prominent"
        title={focused ? 'Caffeine doses' : 'History'}
        actionLabel="Export"
        onAction={exportCurrentSection}
      />

      {!focused ? <SegmentedControl
          value={section}
          onChange={setSection}
          options={[
            { key: 'doses', label: 'Doses' },
            { key: 'vigilance', label: 'Vigilance' },
          ]}
        /> : null}

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
                  ...typeRamp.subheadline,
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
                      gap: spacing.sm,
                      paddingTop: index === 0 ? 0 : 14,
                      borderTopWidth: index === 0 ? 0 : 1,
                      borderColor: palette.separator,
                    }}
                  >
                    <View style={{ gap: spacing.xxs }}>
                      <Text
                        style={{
                          ...typeRamp.body,
                          fontWeight: '600',
                          color: palette.textPrimary,
                        }}
                      >
                        {dose.mg} mg{dose.source ? ` • ${dose.source}` : ''}
                      </Text>
                      <Text
                        style={{
                          ...typeRamp.footnote,
                          color: palette.textSecondary,
                        }}
                      >
                        {fmtDateTime(dose.timestamp)}
                      </Text>
                      {dose.note ? (
                        <Text
                          style={{
                            ...typeRamp.footnote,
                            color: palette.textTertiary,
                          }}
                        >
                          {dose.note}
                        </Text>
                      ) : null}
                    </View>

                    {isEditing ? (
                      <View style={{ gap: spacing.sm }}>
                        <View style={{ flexDirection: 'row', gap: spacing.sm }}>
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
                        <View style={{ flexDirection: 'row', gap: spacing.sm }}>
                          <Button
                            title="Save"
                            variant="primary"
                            onPress={saveEdit}
                          />
                          <Button
                            title="Cancel"
                            variant="tinted"
                            onPress={() => setEditingId(null)}
                          />
                        </View>
                      </View>
                    ) : (
                      <View style={{ flexDirection: 'row', gap: spacing.sm }}>
                        <Button
                          title="Edit"
                          variant="tinted"
                          onPress={() => {
                            setEditingId(dose.id);
                            setDraftMg(String(dose.mg));
                            setDraftSource(dose.source || '');
                          }}
                        />
                        <Button
                          title="Delete"
                          variant="plain"
                          role="destructive"
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
                ...typeRamp.subheadline,
                color: palette.textSecondary,
              }}
            >
              No vigilance sessions yet. Run the reaction test from Summary to
              start building a baseline.
            </Text>
          ) : (
            vigilanceSessions.map((session, index) => (
              <View
                key={session.id}
                style={{
                  gap: spacing.xs,
                  paddingTop: index === 0 ? 0 : 14,
                  borderTopWidth: index === 0 ? 0 : 1,
                  borderColor: palette.separator,
                }}
              >
                <View
                  style={{
                    flexDirection: 'row',
                    alignItems: 'flex-start',
                    gap: spacing.sm,
                  }}
                >
                  <View style={{ flex: 1, gap: spacing.xxs }}>
                    <Text
                      style={{
                        ...typeRamp.body,
                        fontWeight: '600',
                        color: palette.textPrimary,
                      }}
                    >
                      {session.score} {session.rating}
                    </Text>
                    <Text
                      style={{
                        ...typeRamp.footnote,
                        color: palette.textSecondary,
                      }}
                    >
                      {fmtDateTime(session.completedAt)}
                    </Text>
                    <Text
                      style={{
                        ...typeRamp.footnote,
                        color: palette.textTertiary,
                      }}
                    >
                      Median {session.medianReactionMs ?? '—'} ms • Lapses{' '}
                      {session.lapseCount} • False starts{' '}
                      {session.falseStartCount}
                    </Text>
                  </View>
                  <View
                    style={{
                      minWidth: 88,
                      paddingHorizontal: spacing.sm,
                      paddingVertical: spacing.sm,
                      borderRadius: radii.card,
                      backgroundColor: palette.cardMuted,
                      borderWidth: 1,
                      borderColor: palette.cardBorder,
                      alignItems: 'center',
                    }}
                  >
                    <Text
                      style={{
                        ...typeRamp.subheadline,
                        fontWeight: '700',
                        color: palette.textPrimary,
                      }}
                    >
                      {session.validReactionCount}/{session.trialCount}
                    </Text>
                    <Text
                      style={{
                        ...typeRamp.caption,
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
