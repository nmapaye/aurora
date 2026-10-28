import unittest
from verify_xcresult import failures, iteration_failures


class ResultEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.summary = dict(totalTestCount=172, passedTests=172, failedTests=0,
                            skippedTests=0, expectedFailures=0, result="Passed")

    def test_complete_executed_suite_passes(self):
        self.assertEqual(failures(self.summary), [])

    def test_green_exit_with_zero_selected_tests_is_not_acceptance(self):
        self.summary.update(totalTestCount=0, passedTests=0)
        self.assertTrue(failures(self.summary))

    def test_skips_are_not_acceptance(self):
        self.summary.update(passedTests=171, skippedTests=1)
        self.assertTrue(failures(self.summary))

    def test_failures_block(self):
        self.summary.update(passedTests=171, failedTests=1, result="Failed")
        self.assertTrue(failures(self.summary))

    def test_expected_failures_are_not_a_green_beta(self):
        self.summary.update(expectedFailures=1)
        self.assertTrue(failures(self.summary))

    def test_incomplete_receipt_blocks(self):
        del self.summary["passedTests"]
        self.assertTrue(failures(self.summary))

    def test_malformed_counts_block(self):
        self.summary["totalTestCount"] = "172"
        self.assertTrue(failures(self.summary))

    def test_nonfinal_result_blocks(self):
        self.summary["result"] = "In Progress"
        self.assertTrue(failures(self.summary))


class IterationEvidenceTests(unittest.TestCase):
    @staticmethod
    def line(case, status="passed"):
        return f"Test Case '-[AuroraUITests.AuroraUITests {case}]' {status} (30.0 seconds).\n"

    def test_each_named_case_must_complete_all_iterations(self):
        log = (self.line("briefing") + self.line("trends")) * 40
        self.assertEqual(iteration_failures(log, ["briefing", "trends"], 40), [])

    def test_passed_unique_method_is_not_forty_iterations(self):
        self.assertTrue(iteration_failures(self.line("trends"), ["trends"], 40))

    def test_other_case_does_not_hide_missing_case(self):
        self.assertTrue(iteration_failures(self.line("briefing") * 80, ["briefing", "trends"], 40))

    def test_failure_is_not_hidden_by_later_passes(self):
        log = self.line("trends", "failed") + self.line("trends") * 40
        self.assertTrue(iteration_failures(log, ["trends"], 40))

    def test_duplicate_output_is_not_accepted_as_exact_iterations(self):
        self.assertTrue(iteration_failures(self.line("trends") * 80, ["trends"], 40))

    def test_case_name_is_literal_and_must_match_whole_method(self):
        self.assertTrue(iteration_failures(self.line("trendsExtra") * 40, ["trends"], 40))
        self.assertTrue(iteration_failures(self.line("trendsX") * 40, ["trends."], 40))


if __name__ == "__main__":
    unittest.main()
