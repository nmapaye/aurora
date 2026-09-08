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

  // The legacy persisted "granted" status means the request completed, not read permission.
  const requestCompleted = await AppleHealth.requestAuthorization();
  if (!requestCompleted) {
    return {
      status: 'denied',
      message: 'Health access request did not complete. You can continue with manual logging.',
    };
  }

  return {
    status: 'granted',
    message: 'Health request completed. Aurora will check for readable sleep samples.',
  };
}
