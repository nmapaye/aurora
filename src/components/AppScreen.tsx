import React from 'react';
import {
  Pressable,
  ScrollView,
  StyleProp,
  Text,
  View,
  ViewStyle,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useAppScheme from '~/hooks/useAppScheme';
import { navigate } from '~/navigation';
import { getAppPalette } from '~/theme/colors';

type Props = {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  trailing?: React.ReactNode;
  contentStyle?: StyleProp<ViewStyle>;
  centered?: boolean;
  showsVerticalScrollIndicator?: boolean;
  topInset?: number;
};

export default function AppScreen({
  title,
  subtitle,
  children,
  trailing,
  contentStyle,
  centered = false,
  showsVerticalScrollIndicator = false,
  topInset = 8,
}: Props) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const insets = useSafeAreaInsets();
  const layout = useAdaptiveLayout();

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      showsVerticalScrollIndicator={showsVerticalScrollIndicator}
      style={{ flex: 1, backgroundColor: palette.groupedBackground }}
      contentContainerStyle={[
        {
          paddingTop: topInset + layout.topChromeBuffer,
          paddingBottom: 32 + insets.bottom,
          paddingHorizontal: layout.horizontalPadding,
          alignItems: centered || layout.isWideLayout ? 'center' : undefined,
        },
        contentStyle,
      ]}
    >
      <View style={{ width: '100%', maxWidth: layout.contentMaxWidth, gap: 18 }}>
        <View style={{ gap: 12 }}>
          <View
            style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 12 }}
          >
            <View style={{ flex: 1, gap: 4 }}>
              <Text
                style={{
                  fontSize: 40,
                  lineHeight: 46,
                  fontWeight: '700',
                  letterSpacing: 0,
                  color: palette.textPrimary,
                }}
              >
                {title}
              </Text>
              {subtitle ? (
                <Text
                  style={{
                    fontSize: 15,
                    lineHeight: 20,
                    color: palette.textSecondary,
                  }}
                >
                  {subtitle}
                </Text>
              ) : null}
            </View>

            {trailing ?? (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Open settings"
                onPress={() => navigate('Settings')}
                style={({ pressed }) => ({
                  minWidth: 44,
                  minHeight: 44,
                  borderRadius: 22,
                  alignItems: 'center',
                  justifyContent: 'center',
                  backgroundColor: pressed
                    ? palette.pressed
                    : palette.cardMuted,
                  borderWidth: 1,
                  borderColor: palette.cardBorder,
                })}
              >
                <Ionicons
                  name="settings-outline"
                  size={24}
                  color={palette.textPrimary}
                />
              </Pressable>
            )}
          </View>
        </View>
        {children}
      </View>
    </ScrollView>
  );
}
