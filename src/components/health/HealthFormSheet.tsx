import React, { useEffect, useRef } from 'react';
import {
  AccessibilityInfo,
  Modal,
  findNodeHandle,
  Text,
  View,
} from 'react-native';

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
}: Props) {
  const palette = getAppPalette(useAppScheme());
  const headingRef = useRef<Text>(null);

  useEffect(() => {
    if (!visible) return;
    const handle = findNodeHandle(headingRef.current);
    if (handle) AccessibilityInfo.setAccessibilityFocus(handle);
  }, [visible]);

  return (
    <Modal
      testID="health-form-sheet-modal"
      transparent
      visible={visible}
      animationType={reduceMotion ? 'none' : 'slide'}
      onRequestClose={onCancel}
    >
      <View
        accessibilityViewIsModal
        accessibilityLabel={title}
        style={{ flex: 1, justifyContent: 'flex-end', backgroundColor: palette.modalScrim }}
      >
        <View
          style={{
            backgroundColor: palette.modalBackground,
            borderTopLeftRadius: radii.hero,
            borderTopRightRadius: radii.hero,
            padding: spacing.md,
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
        </View>
      </View>
    </Modal>
  );
}
