#!/bin/bash
# BUG-1d (#71) item 1a: keyboard-mode and touch diagnostics for one UI step.
# Usage: keyboard-mode-log.sh <udid> <label>
# Writes build/keyboard-mode-<label>.log, covering only the step that wrote
# build/<label>.started (its start time, in epoch seconds). build/*.log is
# uploaded by "Upload logs". Never fails the job.
set -uo pipefail
udid="$1"; label="$2"
stamp="build/$label.started"
out="build/keyboard-mode-$label.log"
if [ ! -f "$stamp" ]; then
  echo "No $stamp: the $label step did not run, so there is nothing to capture."
  exit 0
fi
minutes=$(( ( $(date +%s) - $(cat "$stamp") ) / 60 + 2 ))
xcrun simctl spawn "$udid" log show --style compact --last "${minutes}m" \
  --predicate 'eventMessage CONTAINS "setMinimized" OR eventMessage CONTAINS "floating assistant" OR eventMessage CONTAINS "touchstats" OR eventMessage CONTAINS "BKSHIDKeyboardDevice" OR eventMessage CONTAINS "visualMode"' \
  > "$out" 2>&1 || true
echo "Captured the last ${minutes} min into $out ($(wc -l < "$out" | tr -d ' ') lines)"
echo "setMinimized lines: $(grep -c setMinimized "$out" || true)"
echo "floating assistant lines: $(grep -c 'floating assistant' "$out" || true)"
echo "BKSHIDKeyboardDevice lines: $(grep -c BKSHIDKeyboardDevice "$out" || true)"
echo "touchstats lines: $(grep -c touchstats "$out" || true)"
echo "soft cancels: $(grep -c 'soft cancel: [1-9]' "$out" || true)"
grep -E 'soft cancel: [1-9]' "$out" | head -20 || true
# Real minimize events only (BUG-1d 1b): not `minimized = 0`, not this log's
# own command line. Diagnostic here; only the iPad probe step fails on it.
python3 "$(dirname "$0")/keyboard_minimize_check.py" "$out" || true
exit 0
