import React, { useState } from 'react';
import type { RefObject } from 'react';
import {
  LayoutChangeEvent,
  NativeScrollEvent,
  NativeSyntheticEvent,
  Pressable,
  ScrollView,
  StyleProp,
  Text,
  View,
  ViewStyle,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import AppIcon, { appIcons } from '~/components/AppIcon';
import { getAppScreenBottomPadding } from '~/components/appScreenLayout';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useAppScheme from '~/hooks/useAppScheme';
import { navigate } from '~/navigation';
import { getAppPalette } from '~/theme/colors';
import {
  fontScaling,
  iconSizes,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';

type Props = {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  trailing?: React.ReactNode;
  contentStyle?: StyleProp<ViewStyle>;
  centered?: boolean;
  showsVerticalScrollIndicator?: boolean;
  topInset?: number;
  scrollRef?: RefObject<ScrollView | null>;
  contentRef?: RefObject<View | null>;
  scrollEnabled?: boolean;
  interactionEnabled?: boolean;
  bottomOverlay?: React.ReactNode;
  headerTransform?: (header: React.ReactNode) => React.ReactNode;
  onScroll?: (event: NativeSyntheticEvent<NativeScrollEvent>) => void;
  onViewportLayout?: (event: LayoutChangeEvent) => void;
};

export default function AppScreen({
  title,
  subtitle,
  children,
  trailing,
  contentStyle,
  centered = false,
  showsVerticalScrollIndicator = false,
  topInset = spacing.xs,
  scrollRef,
  contentRef,
  scrollEnabled = true,
  interactionEnabled = true,
  bottomOverlay,
  headerTransform,
  onScroll,
  onViewportLayout,
}: Props) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const insets = useSafeAreaInsets();
  const layout = useAdaptiveLayout();
  const [overlayHeight, setOverlayHeight] = useState(0);
  const bottomPadding = getAppScreenBottomPadding(
    insets.bottom,
    bottomOverlay ? overlayHeight : 0,
  );

  const header = (
    <View style={{ gap: spacing.sm }}>
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'flex-start',
          gap: spacing.sm,
        }}
      >
        <View style={{ flex: 1, gap: spacing.xxs }}>
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{
              ...typeRamp.largeTitle,
              letterSpacing: 0,
              color: palette.textPrimary,
            }}
          >
            {title}
          </Text>
          {subtitle ? (
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{
                ...typeRamp.subheadline,
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
              borderRadius: radii.capsule,
              alignItems: 'center',
              justifyContent: 'center',
              backgroundColor: pressed
                ? palette.pressed
                : palette.cardMuted,
              borderWidth: 1,
              borderColor: palette.cardBorder,
            })}
          >
            <AppIcon
              name={appIcons.settings}
              size={iconSizes.button}
              color={palette.textPrimary}
            />
          </Pressable>
        )}
      </View>
    </View>
  );

  return (
    <View
      testID="app-screen-root"
      onLayout={onViewportLayout}
      style={{ flex: 1, backgroundColor: palette.groupedBackground }}
    >
      <ScrollView
        testID="app-screen-scroll"
        ref={scrollRef}
        contentInsetAdjustmentBehavior="automatic"
        showsVerticalScrollIndicator={showsVerticalScrollIndicator}
        scrollEnabled={scrollEnabled}
        onScroll={onScroll}
        scrollEventThrottle={16}
        style={{ flex: 1, backgroundColor: palette.groupedBackground }}
        contentContainerStyle={[
          {
            paddingTop: topInset + layout.topChromeBuffer,
            paddingBottom: bottomPadding,
            paddingHorizontal: layout.horizontalPadding,
            alignItems:
              centered || layout.isWideLayout ? 'center' : undefined,
          },
          contentStyle,
        ]}
      >
        <View
          testID="app-screen-content"
          ref={contentRef}
          pointerEvents={interactionEnabled ? 'auto' : 'none'}
          accessibilityElementsHidden={!interactionEnabled}
          importantForAccessibility={
            interactionEnabled ? 'auto' : 'no-hide-descendants'
          }
          style={{
            width: '100%',
            maxWidth: layout.contentMaxWidth,
            gap: spacing.md,
          }}
        >
          {headerTransform ? headerTransform(header) : header}
          {children}
        </View>
      </ScrollView>
      {bottomOverlay ? (
        <View
          testID="app-screen-overlay"
          pointerEvents="box-none"
          onLayout={(event) =>
            setOverlayHeight(event.nativeEvent.layout.height)
          }
          style={{
            position: 'absolute',
            left: layout.horizontalPadding,
            right: layout.horizontalPadding,
            bottom: spacing.sm,
          }}
        >
          {bottomOverlay}
        </View>
      ) : null}
    </View>
  );
}
