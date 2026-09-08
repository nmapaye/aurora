#!/bin/bash
set -euo pipefail

spike_repo=$(cd "$(dirname "$0")/.." && pwd)
spike_package="$spike_repo/spikes/AuroraNative"
spike_output="$spike_package/output"
spike_application="$spike_output/Aurora Spike.app"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/aurora-spike-clang}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-${TMPDIR:-/tmp}/aurora-spike-module-cache}"

swift build --disable-sandbox --package-path "$spike_package" --product AuroraSpikePreview
spike_binary_dir=$(swift build --disable-sandbox --package-path "$spike_package" --show-bin-path)
mkdir -p "$spike_application/Contents/MacOS" "$spike_application/Contents/Resources"
cp "$spike_binary_dir/AuroraSpikePreview" "$spike_application/Contents/MacOS/AuroraSpikePreview.next"
mv -f "$spike_application/Contents/MacOS/AuroraSpikePreview.next" "$spike_application/Contents/MacOS/AuroraSpikePreview"
cat > "$spike_application/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>AuroraSpikePreview</string>
<key>CFBundleIdentifier</key><string>com.nmapaye.aurora.spike.preview</string>
<key>CFBundleName</key><string>Aurora Spike</string>
<key>CFBundleDisplayName</key><string>Aurora Spike</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Aurora interaction prototype. Example data only.</string>
</dict></plist>
PLIST
codesign --force --sign - "$spike_application"
printf '%s\n' "$spike_application"
