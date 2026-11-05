"""Fixture tests for the BUG-1d 1b keyboard-minimize check (#71).

Run: python3 -m unittest discover -s .github/scripts -p 'test_*.py' -v
"""
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from keyboard_minimize_check import CaptureError, check, main

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "keyboard_minimize"
REAL = FIXTURES / "ipad-probe-41957713689.log"
SYNTHETIC = FIXTURES / "synthetic-minimized.log"
HEAD = "Timestamp               Ty Process[PID:TID]\n"


def run(path):
    out = io.StringIO()
    with redirect_stdout(out):
        code = main([str(path)])
    return code, out.getvalue()


def capture(*lines):
    return HEAD + "\n".join(lines) + "\n"


class RealProbeLog(unittest.TestCase):
    def test_run_41957713689_false_positive_passes(self):
        r = check(REAL.read_text())
        self.assertEqual(r.events, [])
        reasons = sorted(f.reason for f in r.ignored)
        self.assertEqual(len(reasons), 2, reasons)
        self.assertIn("setMinimized with minimized = 0 (not minimized)", reasons)
        self.assertIn("probe tooling process `log`", reasons)
        code, out = run(REAL)
        self.assertEqual(code, 0, out)
        self.assertIn("0 minimize event(s), 2 ignored line(s)", out)

    def test_old_grep_would_have_counted_two(self):
        # Guard that the fixture is the real false positive, not a cleaned copy.
        n = sum(1 for l in REAL.read_text().splitlines()
                if "setMinimized" in l or "floating assistant" in l)
        self.assertEqual(n, 2)


class SyntheticMinimize(unittest.TestCase):
    def test_minimized_1_fails(self):
        r = check(SYNTHETIC.read_text())
        self.assertEqual(len(r.events), 1)
        self.assertEqual(r.events[0].entry.process, "Aurora")
        self.assertIn("minimized = 1", r.events[0].reason)
        code, out = run(SYNTHETIC)
        self.assertEqual(code, 1, out)
        self.assertIn("MINIMIZE (line 7", out)

    def test_bare_setminimized_counts(self):
        # Run 41378408179's failing tap: the string has no value; stay strict.
        r = check(capture("2026-11-02 04:23:11.477 Df Aurora[60679:7ddb4] [com.apple.UIKit:KeyboardUI] -[UIKeyboard setMinimized:]"))
        self.assertEqual(len(r.events), 1)

    def test_yes_counts_and_no_is_ignored(self):
        r = check(capture(
            "2026-11-02 04:23:11.477 Df Aurora[1:a] [com.apple.UIKit:KeyboardUI] -[UIKeyboard setMinimized:] Setting keyboard minimized = YES",
            "2026-11-02 04:23:11.478 Df Aurora[1:a] [com.apple.UIKit:KeyboardUI] -[UIKeyboard setMinimized:] Setting keyboard minimized = NO",
        ))
        self.assertEqual(len(r.events), 1)
        self.assertEqual(len(r.ignored), 1)

    def test_visual_mode_to_minimized_counts(self):
        r = check(capture(
            "2026-11-02 04:23:11.477 Df Aurora[1:a] [com.apple.UIKit:KeyboardUI] visualMode 1 -> 2",
            "2026-11-02 04:23:12.000 Df Aurora[1:a] [com.apple.UIKit:KeyboardUI] visualMode 2 -> 1",
        ))
        self.assertEqual([f.reason for f in r.events], ["visualMode 1 -> 2 (minimized)"])
        self.assertEqual(len(r.ignored), 1)

    def test_floating_assistant_from_inputui_counts(self):
        r = check(capture(
            "2026-11-02 04:23:11.490 Df InputUI[3338:d0a] [com.apple.InputUI:Tracking] start | TUIKeyboardTrackingCoordinator | <TUIKeyboardState: 0x115d2a2a0 State: onscreen with floating assistant; is undocked + floating>",
        ))
        self.assertEqual([f.reason for f in r.events], ["floating-assistant presentation"])

    def test_multiline_entry_belongs_to_its_process(self):
        # A continuation line quoting setMinimized stays with the log entry.
        r = check(capture(
            "2026-11-05 03:01:33.440 Df log[19144:0] [com.apple.log:] log run noninteractively, args:",
            "    'eventMessage CONTAINS \"setMinimized\"'",
        ))
        self.assertEqual(r.events, [])
        self.assertEqual(len(r.ignored), 1)


class CaptureProblems(unittest.TestCase):
    def test_missing_file_is_exit_2(self):
        code, out = run(Path(tempfile.gettempdir()) / "no-such-keyboard-probe.log")
        self.assertEqual(code, 2, out)

    def test_non_compact_capture_is_exit_2(self):
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as fh:
            fh.write("log: Could not open local log store\n")
        code, out = run(Path(fh.name))
        self.assertEqual(code, 2, out)
        with self.assertRaises(CaptureError):
            check("garbage\n")

    def test_empty_but_valid_capture_passes(self):
        self.assertEqual(check(HEAD).events, [])


if __name__ == "__main__":
    unittest.main()
