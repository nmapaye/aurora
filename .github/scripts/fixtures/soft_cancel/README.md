# Soft-cancel rerun fixtures (BUG-1d, #71)

- `iphone-skip-soft-cancel.xcodebuild.log`: the failing iteration 15/40 of
  testTrendsSwitchSignalsAndRange from CI run 41378408179 (iPhone job
  125063672007, `xcodebuild-typed-repeat.log` l.7302-7350, lines cut at 400
  characters).
- `ipad-save-normal.xcodebuild.log`: testDraftFieldKeepsSaveAboveCollapsedComposer
  failing at AuroraUITests.swift:496 in the same run (iPad job 125063671988,
  `xcodebuild-test.log` l.1920-2336 plus the summary; the hierarchy dump is
  trimmed).
- `*.touch.ndjson`: the matching backboardd/UIKit/InputUI messages from the
  decoded unified logs, in `log show --style ndjson` form. The decoded logs
  carry simulator continuous-time stamps, so the wall-clock timestamps here
  are placed from the xcodebuild "Start Test at" time plus the tap's offset
  (Skip tap +8.14 s, touchstats about 0.19 s later; Save tap +37.57 s).
