#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
WORKSPACE="$IOS_DIR/AURORA.xcworkspace"
LOCAL_ENV="$IOS_DIR/.xcode.env.local"
POD_INSTALL_ARGS=(install)
COCOAPODS_VERSION="1.16.2"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

command -v xcodebuild >/dev/null 2>&1 ||
  fail "Xcode is not installed or selected. Install stable Xcode 26.6 and select it with xcode-select."
if ! XCODE_OUTPUT="$(xcodebuild -version 2>&1)"; then
  fail "Full Xcode is not selected. Install stable Xcode 26.6, launch it once, and select it with xcode-select."
fi

XCODE_VERSION="$(printf '%s\n' "$XCODE_OUTPUT" | awk 'NR == 1 { print $2 }')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
[[ "$XCODE_MAJOR" =~ ^[0-9]+$ ]] ||
  fail "Could not determine the active Xcode version."
# SDK 57 requires Xcode 26.4+. Keep release builds on the repository's 26.6 target.
[[ "$XCODE_VERSION" =~ ^26\.6(\.[0-9]+)?$ ]] ||
  fail "Stable Xcode 26.6 is required (Expo SDK 57 minimum: 26.4); active version is $XCODE_VERSION."

if ! SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)"; then
  fail "The active Xcode installation does not provide an iOS SDK."
fi
SDK_MAJOR="${SDK_VERSION%%.*}"
SDK_MINOR="${SDK_VERSION#*.}"
SDK_MINOR="${SDK_MINOR%%.*}"
[[ "$SDK_MAJOR" =~ ^[0-9]+$ && "$SDK_MINOR" =~ ^[0-9]+$ ]] ||
  fail "Could not determine the active iOS SDK version."
(( SDK_MAJOR > 26 || (SDK_MAJOR == 26 && SDK_MINOR >= 4) )) ||
  fail "The iOS 26.4 SDK or newer is required; active SDK is $SDK_VERSION."

command -v node >/dev/null 2>&1 ||
  fail "Node.js 24 is required but node was not found."
NODE_BINARY="$(command -v node)"
NODE_VERSION="$(node --version | sed 's/^v//')"
NODE_MAJOR="${NODE_VERSION%%.*}"
[[ "$NODE_MAJOR" == "24" ]] ||
  fail "Node.js 24 is required; active version is $NODE_VERSION."

command -v pod >/dev/null 2>&1 ||
  fail "CocoaPods $COCOAPODS_VERSION is required but pod was not found."
if ! POD_VERSION="$(pod "_${COCOAPODS_VERSION}_" --version 2>/dev/null)"; then
  fail "CocoaPods $COCOAPODS_VERSION is required. Install that exact version before continuing."
fi
[[ "$POD_VERSION" == "$COCOAPODS_VERSION" ]] ||
  fail "CocoaPods $COCOAPODS_VERSION is required; active version is $POD_VERSION."

[[ -d "$WORKSPACE" ]] ||
  fail "Missing $WORKSPACE. Restore the committed Xcode workspace before continuing."

if [[ "${1:-}" == "--deployment" ]]; then
  POD_INSTALL_ARGS+=(--deployment)
  shift
fi
(( $# == 0 )) ||
  fail "Unsupported argument. Use --deployment for a lockfile-enforced pod install."

printf 'export NODE_BINARY="%s"\n' "$NODE_BINARY" > "$LOCAL_ENV"

(
  cd "$IOS_DIR"
  pod "_${COCOAPODS_VERSION}_" "${POD_INSTALL_ARGS[@]}"
)

printf 'Aurora iOS environment is ready.\n'
printf '  Xcode: %s\n' "$XCODE_VERSION"
printf '  iOS SDK: %s\n' "$SDK_VERSION"
printf '  Node: %s (%s)\n' "$NODE_VERSION" "$NODE_BINARY"
printf '  CocoaPods: %s\n' "$POD_VERSION"
printf 'Open: %s\n' "$WORKSPACE"
