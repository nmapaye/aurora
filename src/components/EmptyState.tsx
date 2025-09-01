import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  StyleProp,
  ViewStyle,
} from 'react-native';
import Button from './Button';
import { colors } from '../theme/colors';

type Props = {
  title: string;
  message?: string;
  icon?: React.ReactNode;
  actionLabel?: string;
  onAction?: () => void;
  secondaryLabel?: string;
  onSecondary?: () => void;
  style?: StyleProp<ViewStyle>;
  testID?: string;
};

export default function EmptyState({
  title,
  message,
  icon,
  actionLabel,
  onAction,
  secondaryLabel,
  onSecondary,
  style,
  testID,
}: Props) {
  return (
    <View style={[styles.wrap, style]} testID={testID}>
      <View style={styles.iconWrap}>
        {icon ?? <Text style={styles.emoji}>☕️</Text>}
      </View>
      <Text style={styles.title}>{title}</Text>
      {message ? <Text style={styles.message}>{message}</Text> : null}
      {(actionLabel || secondaryLabel) ? (
        <View style={styles.row}>
          {actionLabel ? (
            <Button
              title={actionLabel}
              variant="primary"
              onPress={onAction}
              style={{ minWidth: 120 }}
            />
          ) : null}
          {secondaryLabel ? (
            <Button
              title={secondaryLabel}
              variant="outline"
              onPress={onSecondary}
              style={{ minWidth: 120 }}
            />
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 24,
    paddingHorizontal: 16,
    gap: 12,
  },
  iconWrap: {
    height: 64,
    width: 64,
    borderRadius: 32,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
  },
  emoji: { fontSize: 28, color: colors.textPrimary },
  title: {
    color: colors.textPrimary,
    fontSize: 18,
    fontWeight: '600',
    textAlign: 'center',
  },
  message: {
    color: colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
  },
  row: {
    marginTop: 8,
    flexDirection: 'row',
    gap: 12,
  },
});