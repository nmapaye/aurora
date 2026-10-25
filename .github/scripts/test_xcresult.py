import unittest
from verify_xcresult import failures


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


if __name__ == "__main__":
    unittest.main()
