"""Fixture tests for the BUG-1d soft-cancel rerun rule (#71).

Run: python3 -m unittest discover -s .github/scripts -p 'test_*.py' -v
"""
import json
import tempfile
import unittest
from pathlib import Path

from soft_cancel_rerun import classify, parse_touch_log, run_step, _offset

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "soft_cancel"


def fixture(name):
    return (FIXTURES / name).read_text()


SKIP_LOG = fixture("iphone-skip-soft-cancel.xcodebuild.log")
SKIP_TOUCH = fixture("iphone-skip-soft-cancel.touch.ndjson")
SAVE_LOG = fixture("ipad-save-normal.xcodebuild.log")
SAVE_TOUCH = fixture("ipad-save-normal.touch.ndjson")

# A second, unrelated failure in the same step (a Test-step-shaped log).
OTHER_CASE = """Test Case '-[AuroraUITests.AuroraUITests testOfflineChartAndNativeToolsAreReachable]' started.
    t =     0.00s Start Test at 2026-11-02 03:57:00.000
    t =     9.10s     Synthesize event
/Users/runner/work/aurora/aurora/AuroraUITests/AuroraUITests.swift:509: error: -[AuroraUITests.AuroraUITests testOfflineChartAndNativeToolsAreReachable] : XCTAssertTrue failed
Test Case '-[AuroraUITests.AuroraUITests testOfflineChartAndNativeToolsAreReachable]' failed (12.000 seconds).
"""


class ClassifierTests(unittest.TestCase):
    def test_soft_cancel_only_failure_allows_one_rerun(self):
        d = classify(SKIP_LOG, SKIP_TOUCH, "+0000")
        self.assertTrue(d.rerun, d.report())
        self.assertEqual(d.test, "testTrendsSwitchSignalsAndRange")
        self.assertEqual(d.iteration, "15 of 40")
        self.assertIn("AuroraUITests.swift:41", d.failure)
        self.assertIn("soft cancel: 1", d.touch_line)
        self.assertIn("Aurora.10706", d.touch_line)
        report = d.report()
        for needed in ("SOFT-CANCEL RERUN: yes", "testTrendsSwitchSignalsAndRange", "15 of 40", "soft cancel: 1"):
            self.assertIn(needed, report)

    def test_normal_assertion_failure_without_soft_cancel_gets_no_rerun(self):
        d = classify(SAVE_LOG, SAVE_TOUCH, "+0000")
        self.assertFalse(d.rerun, d.report())
        self.assertEqual(d.test, "testDraftFieldKeepsSaveAboveCollapsedComposer")
        self.assertIn("AuroraUITests.swift:496", d.failure)
        self.assertIn("no backboardd soft cancel", d.reason)

    def test_soft_cancel_plus_a_second_failure_gets_no_rerun(self):
        log = SKIP_LOG.replace("Test Suite 'AuroraUITests' failed", OTHER_CASE + "Test Suite 'AuroraUITests' failed", 1)
        d = classify(log, SKIP_TOUCH, "+0000")
        self.assertFalse(d.rerun, d.report())
        self.assertIn("2 failed test cases", d.reason)

    def test_two_failures_in_the_failing_test_get_no_rerun(self):
        err = next(l for l in SKIP_LOG.splitlines() if ": error: -[" in l)
        d = classify(SKIP_LOG.replace(err, err + "\n" + err.replace(":41:", ":42:"), 1), SKIP_TOUCH, "+0000")
        self.assertFalse(d.rerun, d.report())

    def test_summary_with_more_than_one_failure_gets_no_rerun(self):
        log = SKIP_LOG.replace("with 1 failure (0 unexpected)", "with 2 failures (0 unexpected)")
        self.assertFalse(classify(log, SKIP_TOUCH, "+0000").rerun)

    def test_a_crash_gets_no_rerun_even_with_a_soft_cancel(self):
        log = SKIP_LOG.replace("    t =    14.55s Tear Down", "    t =    14.50s Aurora (10706) crashed\n    t =    14.55s Tear Down")
        d = classify(log, SKIP_TOUCH, "+0000")
        self.assertFalse(d.rerun)
        self.assertIn("non-assertion", d.reason)

    def test_soft_cancel_on_a_different_tap_gets_no_rerun(self):
        moved = SKIP_TOUCH.replace("2026-11-02 03:56:24.497200", "2026-11-02 03:56:40.000000")
        d = classify(SKIP_LOG, moved, "+0000")
        self.assertFalse(d.rerun, d.report())

    def test_soft_cancel_from_another_process_does_not_count(self):
        other = SKIP_TOUCH.replace('"/usr/libexec/backboardd"', '"/usr/bin/fake"')
        self.assertFalse(classify(SKIP_LOG, other, "+0000").rerun)

    def test_missing_touch_log_gets_no_rerun(self):
        d = classify(SKIP_LOG, "", "+0000")
        self.assertFalse(d.rerun)
        self.assertIn("no captured touch log", d.reason)

    def test_wrong_runner_offset_fails_safe(self):
        # A runner clock read as UTC-8 puts the tap 8 hours away from the log.
        self.assertFalse(classify(SKIP_LOG, SKIP_TOUCH, "-0800").rerun)

    def test_passing_log_gets_no_rerun(self):
        passed = SKIP_LOG.replace("' failed (14.825 seconds)", "' passed (14.825 seconds)")
        passed = "\n".join(l for l in passed.splitlines() if ": error: -[" not in l)
        self.assertFalse(classify(passed, SKIP_TOUCH, "+0000").rerun)

    def test_the_rerun_itself_is_never_rerun(self):
        d = classify(SKIP_LOG, SKIP_TOUCH, "+0000", attempt=2)
        self.assertFalse(d.rerun)
        self.assertIn("no third attempt", d.reason)

    def test_compact_style_with_continuation_lines(self):
        compact = (
            "Timestamp               Ty Process[PID:TID]\n"
            "2026-11-02 03:56:24.497 Df backboardd[2762:3a1] [com.apple.backboard.hid:touch] touchstats 105B5D0000350-<main>\n"
            "    down: 1,\n    up: 1,\n    soft cancel: 1,\n    destinations: {\n        Aurora.10706 contextID BF43373E: {\n"
        )
        entries = parse_touch_log(compact, _offset("+0000"))
        self.assertEqual(len(entries), 1)
        self.assertIn("soft cancel: 1", entries[0][2])
        self.assertTrue(classify(SKIP_LOG, compact, "+0000").rerun)


class RunStepTests(unittest.TestCase):
    """The step runner: one rerun at most, and a failed rerun fails the step."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.log = self.dir / "xcodebuild-typed-repeat.log"
        self.result = self.dir / "TypedRequestRepeat.xcresult"
        self.touch = self.dir / "keyboard-mode-typed"
        self.calls = []
        self.out = []

    def runner(self, outcomes):
        """outcomes: one (status, log text) per xcodebuild attempt."""
        queue = list(outcomes)

        def run(cmd, log):
            self.calls.append((list(cmd), log))
            if cmd[0] == "verify":
                return 0
            status, text = queue.pop(0)
            log.write_text(text)
            return status
        return run

    def capture(self, udid, out, seconds):
        out.write_text(SKIP_TOUCH)

    def go(self, outcomes, verify=("verify", "{result}", "--iteration-log", "{log}")):
        return run_step(["xcodebuild", "test-without-building"], self.log, self.result, list(verify), "UDID",
                        self.touch, "+0000", runner=self.runner(outcomes), capture=self.capture,
                        clock=lambda: 0.0, emit=self.out.append)

    def xcodebuild_calls(self):
        return [c for c in self.calls if c[0][0] == "xcodebuild"]

    def test_failed_rerun_fails_the_job_with_no_third_attempt(self):
        status = self.go([(65, SKIP_LOG), (65, SKIP_LOG)])
        self.assertEqual(status, 65)
        self.assertEqual(len(self.xcodebuild_calls()), 2)
        text = "\n".join(self.out)
        self.assertIn("rerunning this step once: testTrendsSwitchSignalsAndRange iteration 15 of 40", text)
        self.assertIn("soft cancel: 1", text)
        self.assertIn("no third attempt", text)

    def test_soft_cancel_rerun_that_passes_turns_the_step_green_and_says_so(self):
        status = self.go([(65, SKIP_LOG), (0, "** TEST EXECUTE SUCCEEDED **")])
        self.assertEqual(status, 0)
        calls = self.xcodebuild_calls()
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[1][0][-1], str(self.dir / "TypedRequestRepeat-Rerun.xcresult"))
        self.assertEqual(calls[1][1], self.dir / "xcodebuild-typed-repeat-rerun.log")
        verify = [c for c in self.calls if c[0][0] == "verify"]
        self.assertEqual(verify[-1][0], ["verify", str(self.dir / "TypedRequestRepeat-Rerun.xcresult"),
                                         "--iteration-log", str(self.dir / "xcodebuild-typed-repeat-rerun.log")])
        self.assertTrue(any("the rerun passed" in line for line in self.out))

    def test_normal_failure_runs_once(self):
        def capture(udid, out, seconds):
            out.write_text(SAVE_TOUCH)
        status = run_step(["xcodebuild"], self.log, self.result, [], "UDID", self.touch, "+0000",
                          runner=self.runner([(65, SAVE_LOG)]), capture=capture, clock=lambda: 0.0,
                          emit=self.out.append)
        self.assertEqual(status, 65)
        self.assertEqual(len(self.xcodebuild_calls()), 1)
        self.assertIn("SOFT-CANCEL RERUN: no", self.out[0])

    def test_green_first_attempt_runs_once_and_captures_nothing(self):
        captured = []
        status = run_step(["xcodebuild"], self.log, self.result, ["verify"], "UDID", self.touch, "+0000",
                          runner=self.runner([(0, "ok")]), capture=lambda *a: captured.append(a),
                          clock=lambda: 0.0, emit=self.out.append)
        self.assertEqual(status, 0)
        self.assertEqual(len(self.xcodebuild_calls()), 1)
        self.assertEqual(captured, [])
        self.assertEqual(self.out, [])


if __name__ == "__main__":
    unittest.main()
