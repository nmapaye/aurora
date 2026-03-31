import React from 'react';
import {
  Pressable,
  ScrollView,
  StyleProp,
  Text,
  View,
  ViewStyle,
  useColorScheme,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

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
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const insets = useSafeAreaInsets();

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      showsVerticalScrollIndicator={showsVerticalScrollIndicator}
      style={{ flex: 1, backgroundColor: palette.groupedBackground }}
      contentContainerStyle={[
        {
          paddingTop: topInset,
          paddingBottom: 32 + insets.bottom,
          paddingHorizontal: 16,
          alignItems: centered ? 'center' : undefined,
        },
        contentStyle,
      ]}
    >
      <View style={{ width: '100%', maxWidth: 600, gap: 18 }}>
        <View style={{ gap: 12 }}>
          <View
            style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 12 }}
          >
            <View style={{ flex: 1, gap: 4 }}>
              <Text
                style={{
                  fontSize: 34,
                  lineHeight: 41,
                  fontWeight: '700',
                  letterSpacing: -0.6,
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
                  minWidth: 36,
                  minHeight: 36,
                  borderRadius: 18,
                  alignItems: 'center',
                  justifyContent: 'center',
                  backgroundColor: pressed
                    ? palette.pressed
                    : palette.card,
                  borderWidth: 1,
                  borderColor: palette.cardBorder,
                })}
              >
                <Ionicons
                  name="settings-outline"
                  size={18}
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
