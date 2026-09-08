#!/bin/bash
set -euo pipefail

spike_repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$spike_repo"
spike_output="$spike_repo/ios/build/SpikeReview/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$spike_output"

spike_runtime=$(xcrun simctl list runtimes --json | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]]
if not runtimes:
    sys.exit("No available iOS simulator runtime. Install one in Xcode Settings > Components.")
print(max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))["identifier"])
')
spike_ipad=$(xcrun simctl list devicetypes --json | python3 -c '
import json, sys
types = json.load(sys.stdin)["devicetypes"]
matches = [t for t in types if t["name"] == "iPad Air (5th generation)"]
if not matches:
    matches = [t for t in types if t["name"].startswith("iPad Air")]
if not matches:
    sys.exit("No iPad Air simulator device type is available.")
print(matches[0]["identifier"])
')

spike_device=""
cleanup_spike_device() {
    if [[ -n "$spike_device" ]]; then
        xcrun simctl shutdown "$spike_device" >/dev/null 2>&1 || true
        xcrun simctl delete "$spike_device" >/dev/null 2>&1 || true
    fi
}
trap cleanup_spike_device EXIT
for spike_form in iphone ipad; do
    if [[ "$spike_form" == iphone ]]; then
        spike_type=com.apple.CoreSimulator.SimDeviceType.iPhone-13
    else
        spike_type="$spike_ipad"
    fi
    spike_device=$(xcrun simctl create "Aurora Spike $spike_form" "$spike_type" "$spike_runtime")
    xcrun simctl boot "$spike_device"
    xcrun simctl bootstatus "$spike_device" -b
    xcodebuild -workspace ios/AURORA.xcworkspace -scheme AuroraSpike \
        -configuration Debug -destination "platform=iOS Simulator,id=$spike_device" \
        -derivedDataPath ios/build/Spike \
        -resultBundlePath "$spike_output/$spike_form.xcresult" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
    xcrun xcresulttool export attachments --path "$spike_output/$spike_form.xcresult" \
        --output-path "$spike_output/$spike_form-screenshots"
    cleanup_spike_device
    spike_device=""
done
