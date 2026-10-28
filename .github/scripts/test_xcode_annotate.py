"""Regression evidence for the false failedSaveShowsNoReceipt CI diagnosis."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("xcode_annotate", Path(__file__).with_name("xcode-annotate.py"))
annotate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(annotate)


class AnnotationTests(unittest.TestCase):
    def output(self, log):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "xcode.log"
            path.write_text(log)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                annotate.main(path)
            return out.getvalue()

    def test_passing_parameterized_failed_outcome_is_not_an_error(self):
        log = "◇ Test case passing 1 argument outcome → .failed to failedSaveShowsNoReceipt(outcome:) started.\n"
        log += "✔ Test failedSaveShowsNoReceipt(outcome:) passed after 0.001 seconds.\n"
        self.assertEqual(self.output(log), "")

    def test_actual_ui_failure_survives_beside_passing_failed_named_case(self):
        log = "◇ Test case passing 1 argument outcome → .failed to failedSaveShowsNoReceipt(outcome:) started.\n"
        log += "Test Case '-[AuroraUITests.AuroraUITests testLongCardArrivesShowingItsStart]' failed (38.254 seconds).\n"
        output = self.output(log)
        self.assertIn("testLongCardArrivesShowingItsStart", output)
        self.assertNotIn("failedSaveShowsNoReceipt", output)

    def test_swift_testing_and_xctest_suite_failures_are_reported(self):
        for log in ["✘ Test save() failed after 0.1 seconds.\n", "Test Suite 'AuroraTests' failed at 12:00.\n"]:
            with self.subTest(log=log):
                self.assertIn("::error", self.output(log))

    def test_compile_error_is_escaped_and_deduplicated(self):
        line = "/workspace/Aurora/Feature.swift:12:3: error: expected 100%\n"
        output = self.output(line * 2)
        self.assertIn("Feature.swift:12: expected 100%25", output)
        self.assertIn("1-1 of 1", output)


if __name__ == "__main__":
    unittest.main()
