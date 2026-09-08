# Native dependency patches

`react-native-health+1.19.0.patch` guards its legacy event-emitter bridge setup when React Native defines `RCT_REMOVE_LEGACY_ARCH`. React Native 0.86 omits `RCTCallableJSModules.setBridge:` in that mode and injects a callable module with a bridgeless invoker. The patch keeps that injected object instead of replacing it with an unconfigured singleton. Legacy builds retain their original setup.

The HealthKit version is pinned, and `npm ci` applies the patch with `--error-on-fail`. A package update must either carry forward the patch or verify an upstream fix. App CI includes patch changes and must pass the native Debug and Release builds. HealthKit permissions, queries and persisted data are unchanged. Physical-device event delivery remains part of release validation.
