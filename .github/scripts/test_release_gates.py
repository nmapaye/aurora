import unittest
from copy import deepcopy

from check_release_gates import REQUIRED, failures, reporting_failures

SHA = "a" * 40


class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.pages = [{"check_runs": [dict(name=n, head_sha=SHA, app={"id": 15368},
                                            status="completed", conclusion="success") for n in REQUIRED]}]

    def test_private_reporting_must_be_enabled(self):
        self.assertEqual(reporting_failures({"enabled": True}), [])

    def test_disabled_reporting_blocks_release(self):
        self.assertTrue(reporting_failures({"enabled": False}))

    def test_unverified_reporting_blocks_release(self):
        self.assertTrue(reporting_failures({}))

    def test_executed_checks_at_exact_commit_pass(self):
        self.assertEqual(failures(self.pages, SHA), [])

    def test_aggregate_green_does_not_hide_skipped_native_tests(self):
        self.pages[0]["check_runs"][4]["conclusion"] = "skipped"
        self.assertTrue(failures(self.pages, SHA))

    def test_every_non_success_blocks(self):
        for conclusion in ("failure", "cancelled", "timed_out", "neutral", "action_required", None):
            with self.subTest(conclusion=conclusion):
                pages = deepcopy(self.pages)
                pages[0]["check_runs"][0]["conclusion"] = conclusion
                self.assertTrue(failures(pages, SHA))

    def test_in_progress_blocks_even_with_success_conclusion(self):
        self.pages[0]["check_runs"][0]["status"] = "in_progress"
        self.assertTrue(failures(self.pages, SHA))

    def test_stale_sha_blocks(self):
        self.assertTrue(failures(self.pages, "b" * 40))

    def test_missing_check_blocks(self):
        self.pages[0]["check_runs"].pop()
        self.assertTrue(failures(self.pages, SHA))

    def test_name_from_other_app_does_not_satisfy_gate(self):
        self.pages[0]["check_runs"][0]["app"]["id"] = 1
        self.assertTrue(failures(self.pages, SHA))

    def test_ambiguous_duplicate_check_blocks(self):
        self.pages[0]["check_runs"].append(deepcopy(self.pages[0]["check_runs"][0]))
        self.assertTrue(failures(self.pages, SHA))

    def test_checks_on_later_pages_are_required(self):
        checks = self.pages[0]["check_runs"]
        self.assertEqual(failures([{"check_runs": checks[:3]}, {"check_runs": checks[3:]}], SHA), [])


if __name__ == "__main__":
    unittest.main()
