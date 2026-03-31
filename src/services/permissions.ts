import { Platform } from 'react-native';
import AppleHealth from '~/services/platform/health/appleHealth';

import type { HealthPermissionStatus } from '~/state/store';

export type PermissionResult = {
  status: Exclude<HealthPermissionStatus, 'idle'>;
  message: string;
};

export async function requestHealthPermissions(): Promise<PermissionResult> {
  if (Platform.OS !== 'ios') {
    return {
      status: 'unsupported',
      message: 'Health import is currently supported on iPhone only.',
    };
  }

  const available = await AppleHealth.isAvailable();
  if (!available) {
    return {
      status: 'unsupported',
      message: 'HealthKit is not available on this device yet.',
    };
  }

  const granted = await AppleHealth.requestAuthorization();
  if (!granted) {
    return {
      status: 'denied',
      message: 'Health access was not granted. You can continue with manual logging.',
    };
  }

  return {
    status: 'granted',
    message: 'Health access granted. Aurora can now import recent sleep.',
  };
}
