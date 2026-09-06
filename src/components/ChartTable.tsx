import React, { useState } from 'react';
import { Text, View } from 'react-native';
import Button from './Button';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { typeRamp } from '~/theme/tokens';
/** A wrapping, labelled row per plotted point; no fixed cell height or color-only meaning. */
export default function ChartTable({
  title,
  rows,
}: {
  title: string;
  rows: string[];
}) {
  const [expanded, setExpanded] = useState(false),
    palette = getAppPalette(useAppScheme());
  return (
    <View style={{ gap: 8 }}>
      <Button
        title={`${expanded ? 'Hide' : 'Show'} ${title} table`}
        accessibilityValue={{ text: expanded ? 'Expanded' : 'Collapsed' }}
        onPress={() => setExpanded(!expanded)}
      />
      {expanded ? (
        <View style={{ gap: 12 }}>
          {rows.length ? (
            rows.map((row, i) => (
              <Text
                key={i}
                accessible
                accessibilityLabel={row}
                style={{
                  ...typeRamp.body,
                  color: palette.textPrimary,
                  flexShrink: 1,
                }}
              >
                {row}
              </Text>
            ))
          ) : (
            <Text style={{ ...typeRamp.body, color: palette.textPrimary }}>
              No chart data recorded.
            </Text>
          )}
        </View>
      ) : null}
    </View>
  );
}
