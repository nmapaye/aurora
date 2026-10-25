import unittest
from verify_beta_scope import failures


class BetaScopeTests(unittest.TestCase):
    def test_aurora_deep_links_remain_allowed(self):
        self.assertEqual(failures({"CFBundleURLTypes": [{"CFBundleURLSchemes": ["aurora", "com.nmapaye.aurora"]}]}), [])

    def test_no_url_types_is_allowed(self):
        self.assertEqual(failures({}), [])

    def test_google_client_is_rejected(self):
        self.assertTrue(failures({"AuroraGoogleClientID": "fixture.apps.googleusercontent.com"}))

    def test_empty_callback_configuration_is_also_rejected(self):
        self.assertTrue(failures({"AuroraGoogleCallbackScheme": ""}))

    def test_google_callback_in_url_types_is_rejected(self):
        self.assertTrue(failures({"CFBundleURLTypes": [{"CFBundleURLSchemes": ["COM.GOOGLEUSERCONTENT.APPS.fixture"]}]}))

    def test_malformed_root_is_rejected(self):
        self.assertTrue(failures([]))

    def test_malformed_url_types_are_rejected(self):
        for value in ["aurora", ["aurora"]]:
            with self.subTest(value=value):
                self.assertTrue(failures({"CFBundleURLTypes": value}))

    def test_malformed_schemes_are_rejected(self):
        for value in ["aurora", [42]]:
            with self.subTest(value=value):
                self.assertTrue(failures({"CFBundleURLTypes": [{"CFBundleURLSchemes": value}]}))


if __name__ == "__main__":
    unittest.main()
