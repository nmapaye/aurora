#!/bin/bash
set -euo pipefail

spike_repo=$(cd "$(dirname "$0")/.." && pwd)
spike_developer=$(xcode-select -p)
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/aurora-spike-clang}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-${TMPDIR:-/tmp}/aurora-spike-module-cache}"

spike_flags=()
# Command Line Tools ships Testing.framework outside SwiftPM's normal search path.
# Full Xcode supplies the test framework through its SDK/toolchain automatically.
spike_frameworks="$spike_developer/Library/Developer/Frameworks"
if [[ "$spike_developer" == */CommandLineTools && -d "$spike_frameworks/Testing.framework" ]]; then
    spike_flags=(-Xswiftc -F -Xswiftc "$spike_frameworks" -Xlinker -F -Xlinker "$spike_frameworks" -Xlinker -rpath -Xlinker "$spike_frameworks" -Xlinker -rpath -Xlinker "$spike_developer/Library/Developer/usr/lib")
fi
swift test --disable-sandbox --package-path "$spike_repo/spikes/AuroraNative" \
    --enable-swift-testing --disable-xctest "${spike_flags[@]}"
