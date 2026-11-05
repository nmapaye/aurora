# keyboard_minimize fixtures (BUG-1d 1b, #71)

Inputs for `test_keyboard_minimize_check.py`.

- `ipad-probe-41957713689.log`: the real `build/keyboard-mode-probe.log` from
  the iPad job of run 41957713689 (head a571382), unchanged. Its only
  `setMinimized` line is `Setting keyboard minimized = 0` and its only
  `floating assistant` text is the `log` process quoting its own predicate.
  The old `grep -c` counted 2 and failed the job; the check must pass it.
- `synthetic-minimized.log`: synthetic. The same compact format, with the
  Aurora line changed to `minimized = 1`, plus the `log` self-match line. The
  check must fail it with exactly one minimize event.
