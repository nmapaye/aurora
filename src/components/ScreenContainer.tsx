import React from 'react';
import { ScrollView, ViewStyle } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

type Props = {
  children: React.ReactNode;
  center?: boolean;                 // align items center
  topPadding?: number;              // default 12
  bottomPadding?: number;           // default 24
  horizontalPadding?: number;       // default 16
  contentStyle?: ViewStyle;         // extra contentContainerStyle
  showsVerticalScrollIndicator?: boolean;
  keyboardShouldPersistTaps?: 'always' | 'handled' | 'never';
};

export default function ScreenContainer({
  children,
  center,
  topPadding = 12,
  bottomPadding = 24,
  horizontalPadding = 16,
  contentStyle,
  showsVerticalScrollIndicator = false,
  keyboardShouldPersistTaps,
}: Props) {
  const insets = useSafeAreaInsets();
  const pb = bottomPadding + (insets?.bottom ?? 0);
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      showsVerticalScrollIndicator={showsVerticalScrollIndicator}
      keyboardShouldPersistTaps={keyboardShouldPersistTaps}
      contentContainerStyle={{
        paddingTop: topPadding,
        paddingBottom: pb,
        paddingHorizontal: horizontalPadding,
        alignItems: center ? 'center' : undefined,
        ...(contentStyle || {}),
      }}
    >
      {children}
      {/* Bottom spacer to ensure space under last element for home indicator */}
      <></>
    </ScrollView>
  );
}

