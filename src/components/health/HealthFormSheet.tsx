import React, { useEffect, useRef } from 'react';
import type { RefObject } from 'react';
import {
  AccessibilityInfo,
  Modal,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  findNodeHandle,
  Text,
  View,
} from 'react-native';

import { useSafeAreaInsets } from 'react-native-safe-area-context';

import Button from '~/components/Button';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, spacing, typeRamp } from '~/theme/tokens';

type Props = {
  visible: boolean;
  title: string;
  children: React.ReactNode;
  onCancel: () => void;
  onSave: () => void;
  saveLabel?: string;
  saveDisabled?: boolean;
  reduceMotion?: boolean;
  returnFocusRef?: RefObject<View | null>;
};

export function HealthFormSheet({
  visible,
  title,
  children,
  onCancel,
  onSave,
  saveLabel = 'Save',
  saveDisabled = false,
  reduceMotion = false,
  returnFocusRef,
}: Props) {
  const insets = useSafeAreaInsets();
  const palette = getAppPalette(useAppScheme());
  const headingRef = useRef<Text>(null);
  const wasVisibleRef = useRef(false);
  const lastReturnFocusRef = useRef(returnFocusRef);

  useEffect(() => {
    if (visible) {
      lastReturnFocusRef.current = returnFocusRef;
      const handle = findNodeHandle(headingRef.current);
      if (handle) AccessibilityInfo.setAccessibilityFocus(handle);
    } else if (wasVisibleRef.current) {
      // Prefer the trigger named at close: a sheet that deletes its own
      // trigger (an edited row) hands focus to a surviving element instead.
      const target = returnFocusRef?.current ?? lastReturnFocusRef.current?.current ?? null;
      const handle = findNodeHandle(target);
      if (handle) AccessibilityInfo.setAccessibilityFocus(handle);
    }
    wasVisibleRef.current = visible;
  }, [returnFocusRef, visible]);

  // A native iOS page sheet: system corner radius, swipe down to dismiss
  // (routed to onCancel), and a centered card on iPad.
  return (
    <Modal
      testID="health-form-sheet-modal"
      presentationStyle="pageSheet"
      visible={visible}
      animationType={reduceMotion ? 'none' : 'slide'}
      onRequestClose={onCancel}
    >
      <KeyboardAvoidingView
        testID="health-form-keyboard"
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        accessibilityViewIsModal
        accessibilityLabel={title}
        style={{ flex: 1, backgroundColor: palette.modalBackground }}
      >
        <View
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: spacing.xs,
            paddingHorizontal: spacing.xs,
            paddingTop: spacing.xs,
            minHeight: 56,
            borderBottomWidth: 1,
            borderBottomColor: palette.separator,
          }}
        >
          <Button title="Cancel" variant="plain" onPress={onCancel} />
          <Text
            ref={headingRef}
            accessibilityRole="header"
            numberOfLines={1}
            style={{ flex: 1, textAlign: 'center', ...typeRamp.headline, color: palette.textPrimary }}
            maxFontSizeMultiplier={fontScaling.body}
          >
            {title}
          </Text>
          <Button
            title={saveLabel}
            variant="plain"
            disabled={saveDisabled}
            onPress={onSave}
            textStyle={{ fontWeight: '600' }}
          />
        </View>
        <ScrollView
          testID="health-form-scroll"
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="interactive"
          contentContainerStyle={{
            padding: spacing.md,
            paddingBottom: spacing.xl + insets.bottom,
            gap: spacing.md,
          }}
        >
          {children}
        </ScrollView>
      </KeyboardAvoidingView>
    </Modal>
  );
}
