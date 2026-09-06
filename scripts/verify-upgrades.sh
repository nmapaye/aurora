#!/usr/bin/env bash
set -euo pipefail

# Pin the PATH as well as npm: package scripts start Node through /usr/bin/env.
if [[ -x /opt/homebrew/opt/node@24/bin/node ]]; then
  export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
fi
if [[ "$(node -p 'process.versions.node.split(".")[0]')" != 24 ]]; then
  echo 'Verification requires Node 24 on PATH.' >&2
  exit 1
fi

UPGRADE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$UPGRADE_ROOT"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --native ) ]]; then
  echo 'Usage: bash scripts/verify-upgrades.sh [--native]' >&2
  exit 1
fi

if [[ "${1:-}" == --native ]]; then
  if ! UPGRADE_XCODE_VERSION="$(xcodebuild -version 2>&1)"; then
    echo 'Native verification requires full stable Xcode 26.6 selected with xcode-select.' >&2
    exit 1
  fi
  if ! printf '%s\n' "$UPGRADE_XCODE_VERSION" | /usr/bin/grep -Eq '^Xcode 26\.6(\.[0-9]+)?$' ||
     ! printf '%s\n' "$UPGRADE_XCODE_VERSION" | /usr/bin/grep -Eq '^Build version [0-9]+[A-Z][0-9]+$'; then
    echo 'Native verification requires stable Xcode 26.6, without a beta build suffix.' >&2
    exit 1
  fi
  UPGRADE_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
  if [[ "$UPGRADE_SDK_VERSION" != 26.* ]]; then
    echo 'Native verification requires the iOS 26 SDK.' >&2
    exit 1
  fi
fi

node --version
npm run type-check
npm run lint
npm test -- --runInBand
TZ=America/New_York npm test -- --runInBand --runTestsByPath tests/utils/calendar.spec.ts tests/features/sleep/routines.review.spec.ts tests/features/planning/model.review.spec.ts
npm exec -- expo export --platform ios
npm run site:type-check
npm run site:build

if [[ "${1:-}" == --native ]]; then
  npm run ios:build:debug
  npm run ios:build:release
else
  echo 'Application checks passed. Native build and device acceptance gates remain separate.'
fi
