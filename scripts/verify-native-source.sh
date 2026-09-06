#!/usr/bin/env bash
set -euo pipefail
AURORA_SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$AURORA_SOURCE_ROOT"
AURORA_SOURCE_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/aurora-native-source.XXXXXX")"
trap 'rm -rf "$AURORA_SOURCE_TEMP"' EXIT

xcrun swiftc -frontend -parse \
  modules/aurora-native/ios/AuroraNativeModule.swift \
  modules/aurora-native/ios/Shared/AuroraSnapshot.swift \
  modules/aurora-native/ios/Shared/AuroraNapAttributes.swift \
  ios/AuroraWidgets/AuroraWidgets.swift \
  ios/AURORA/AuroraIntents.swift
xcrun swiftc \
  modules/aurora-native/ios/Shared/AuroraSnapshot.swift \
  tests/native/SnapshotReview.swift \
  -o "$AURORA_SOURCE_TEMP/snapshot-review"
"$AURORA_SOURCE_TEMP/snapshot-review"
plutil -lint ios/AURORA.xcodeproj/project.pbxproj \
  ios/AURORA/Info.plist ios/AURORA/AURORA.entitlements \
  ios/AuroraWidgets/Info.plist ios/AuroraWidgets/AuroraWidgets.entitlements
ruby -c modules/aurora-native/ios/AuroraNative.podspec
printf '%s\n' 'Source checks passed. iOS SDK type-checking, native builds, signing and device acceptance are still required.'
