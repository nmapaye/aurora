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
import { fontScaling, radii, spacing, typeRamp } from '~/theme/tokens';

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
      const handle = findNodeHandle(lastReturnFocusRef.current?.current ?? null);
      if (handle) AccessibilityInfo.setAccessibilityFocus(handle);
    }
    wasVisibleRef.current = visible;
  }, [returnFocusRef, visible]);

  return (
    <Modal
      testID="health-form-sheet-modal"
      transparent
      visible={visible}
      animationType={reduceMotion ? 'none' : 'slide'}
      onRequestClose={onCancel}
    >
      <KeyboardAvoidingView
        testID="health-form-keyboard"
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        accessibilityViewIsModal
        accessibilityLabel={title}
        style={{ flex: 1, paddingTop: insets.top, justifyContent: 'flex-end', backgroundColor: palette.modalScrim }}
      >
        <ScrollView
          testID="health-form-scroll"
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="interactive"
          style={{ flexGrow: 0, flexShrink: 1, backgroundColor: palette.modalBackground,
            borderTopLeftRadius: radii.hero, borderTopRightRadius: radii.hero }}
          contentContainerStyle={{
            backgroundColor: palette.modalBackground,
            borderTopLeftRadius: radii.hero,
            borderTopRightRadius: radii.hero,
            padding: spacing.md,
            paddingBottom: spacing.md + insets.bottom,
            gap: spacing.md,
          }}
        >
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.sm }}>
            <Text
              ref={headingRef}
              accessibilityRole="header"
              style={{ flex: 1, ...typeRamp.title3, color: palette.textPrimary }}
              maxFontSizeMultiplier={fontScaling.body}
            >
              {title}
            </Text>
            <Button title="Cancel" variant="plain" onPress={onCancel} />
          </View>
          {children}
          <Button title={saveLabel} variant="primary" disabled={saveDisabled} onPress={onSave} />
        </ScrollView>
      </KeyboardAvoidingView>
    </Modal>
  );
}
