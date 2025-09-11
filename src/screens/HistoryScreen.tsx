import React, { useMemo, useState } from 'react';
import { View, Text, Pressable, TextInput, PlatformColor, Share } from 'react-native';
import ScreenContainer from '~/components/ScreenContainer';
import { useStore } from '~/state/store';

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

export default function HistoryScreen() {
  const doses = useStore((s) => s.doses);
  const updateDose = useStore((s) => (s as any).updateDose as (id: string, patch: any) => void);
  const removeDose = useStore((s) => (s as any).removeDose as (id: string) => void);

  // Filters
  type RangeKey = '7' | '14' | '30' | 'all';
  const [range, setRange] = useState<RangeKey>('7');
  const [query, setQuery] = useState('');

  const now = Date.now();
  const rangeStart = useMemo(() => {
    if (range === 'all') return 0;
    const days = range === '7' ? 7 : range === '14' ? 14 : 30;
    const d = new Date(); d.setHours(23,59,59,999);
    return d.getTime() - (days * 24 * 3600 * 1000);
  }, [range]);

  const items = useMemo(() => {
    const q = query.trim().toLowerCase();
    return [...doses]
      .filter(d => d.timestamp >= rangeStart)
      .filter(d => q ? (`${d.mg}`.includes(q) || (d.source||'').toLowerCase().includes(q) || (d.note||'').toLowerCase().includes(q)) : true)
      .sort((a, b) => b.timestamp - a.timestamp);
  }, [doses, rangeStart, query]);

  const [editingId, setEditingId] = useState<string | null>(null);
  const [draftMg, setDraftMg] = useState<number>(0);
  const [draftSource, setDraftSource] = useState<string>('');
  const startEdit = (id: string, mg: number) => { setEditingId(id); setDraftMg(mg); };
  const saveEdit = () => { if (editingId) { updateDose(editingId, { mg: Math.max(1, Math.round(draftMg)), source: draftSource || undefined }); setEditingId(null); } };

  const fmt = (t: number) => {
    try { return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(t)); }
    catch { return new Date(t).toLocaleString(); }
  };

  return (
    <ScreenContainer>
      <View style={{ width: '100%', maxWidth: 560, gap: 16 }}>
        <Panel>
          {/* Controls */}
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            {(['7','14','30','all'] as RangeKey[]).map((k) => {
              const active = range === k;
              const label = k === 'all' ? 'All' : `${k}d`;
              return (
                <Pressable
                  key={k}
                  onPress={() => setRange(k)}
                  accessibilityRole="button"
                  accessibilityState={{ selected: active }}
                  style={{ paddingHorizontal: 12, paddingVertical: 8, borderRadius: 999, backgroundColor: active ? PlatformColor('systemFill') : PlatformColor('tertiarySystemBackground'), borderWidth: 1, borderColor: PlatformColor('separator') }}
                >
                  <Text style={{ color: PlatformColor('label') }}>{label}</Text>
                </Pressable>
              );
            })}
            <View style={{ flex: 1 }} />
            <Pressable
              onPress={async () => {
                const header = 'id,timestamp,datetime,mg,source,note';
                const lines = items.map(d => {
                  const dt = new Date(d.timestamp);
                  const iso = dt.toISOString();
                  const fields = [d.id, String(d.timestamp), iso, String(d.mg), (d.source||''), (d.note||'')]
                    .map(v => '"' + String(v).replace(/"/g,'""') + '"');
                  return fields.join(',');
                });
                const csv = [header, ...lines].join('\n');
                await Share.share({ message: csv });
              }}
              accessibilityRole="button"
              style={{ minHeight: HIT_TARGET, paddingHorizontal: 12, borderRadius: 12, alignItems:'center', justifyContent:'center', backgroundColor: PlatformColor('tintColor') }}
            >
              <Text style={{ color: '#fff', fontWeight: '600' }}>Export CSV</Text>
            </Pressable>
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
          {items.length === 0 ? (
            <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
              No doses logged yet.
            </Text>
          ) : (
            items.map((d, idx) => (
              <View key={d.id} style={{ paddingVertical: 10, borderTopWidth: idx === 0 ? 0 : 1, borderColor: PlatformColor('separator') }}>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontSize: 17, lineHeight: 22, color: PlatformColor('label') }}>{d.mg} mg {d.source ? `• ${d.source}` : ''}</Text>
                    <Text style={{ fontSize: 13, lineHeight: 18, color: PlatformColor('secondaryLabel') }}>{fmt(d.timestamp)}</Text>
                  </View>
                  {editingId === d.id ? (
                    <>
                      <TextInput
                        value={String(draftMg)}
                        onChangeText={(t) => setDraftMg(parseInt(t || '0', 10))}
                        keyboardType="number-pad"
                        style={{ minWidth: 64, textAlign: 'center', borderBottomWidth: 1, borderColor: PlatformColor('separator'), color: PlatformColor('label') }}
                      />
                      <TextInput
                        value={draftSource}
                        onChangeText={setDraftSource}
                        placeholder="Source"
                        placeholderTextColor={PlatformColor('tertiaryLabel')}
                        style={{ minWidth: 96, textAlign: 'left', borderBottomWidth: 1, borderColor: PlatformColor('separator'), color: PlatformColor('label') }}
                      />
                      <Pressable onPress={saveEdit} accessibilityRole="button" style={{ minHeight: HIT_TARGET, paddingHorizontal: 12, borderRadius: 10, backgroundColor: PlatformColor('tintColor'), alignItems: 'center', justifyContent: 'center' }}>
                        <Text style={{ color: '#fff', fontWeight: '600' }}>Save</Text>
                      </Pressable>
                      <Pressable onPress={() => setEditingId(null)} accessibilityRole="button" style={{ minHeight: HIT_TARGET, paddingHorizontal: 12, borderRadius: 10, backgroundColor: PlatformColor('systemFill'), alignItems: 'center', justifyContent: 'center' }}>
                        <Text style={{ color: PlatformColor('label') }}>Cancel</Text>
                      </Pressable>
                    </>
                  ) : (
                    <>
                      <Pressable onPress={() => { startEdit(d.id, d.mg); setDraftSource(d.source || ''); }} accessibilityRole="button" style={{ minHeight: HIT_TARGET, paddingHorizontal: 12, borderRadius: 10, backgroundColor: PlatformColor('systemFill'), alignItems: 'center', justifyContent: 'center' }}>
                        <Text style={{ color: PlatformColor('label') }}>Edit</Text>
                      </Pressable>
                      <Pressable onPress={() => removeDose(d.id)} accessibilityRole="button" style={{ minHeight: HIT_TARGET, paddingHorizontal: 12, borderRadius: 10, backgroundColor: PlatformColor('systemFill'), alignItems: 'center', justifyContent: 'center' }}>
                        <Text style={{ color: PlatformColor('label') }}>Delete</Text>
                      </Pressable>
                    </>
                  )}
                </View>
              </View>
            ))
          )}
        </Panel>
      </View>
    </ScreenContainer>
  );
}
