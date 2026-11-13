"""Portable regression for variadic lipo argument order; not an Apple SDK test."""
import pathlib
import shlex
import unittest


def valid_lipo_order(command):
    args = shlex.split(command)
    return args == ['lipo', '$app/Aurora', '-verify_arch', 'arm64']


class UnsignedArtifactWorkflowTests(unittest.TestCase):
    def test_rejects_original_variadic_argument_bug(self):
        self.assertFalse(valid_lipo_order('lipo -verify_arch arm64 "$app/Aurora"'))

    def test_keeps_binary_before_architecture_assertion(self):
        source = (pathlib.Path(__file__).resolve().parents[1] / 'workflows/ios-app-ci.yml').read_text()
        commands = [line.strip() for line in source.splitlines() if line.strip().startswith('lipo ')]
        self.assertEqual(len(commands), 1)
        self.assertTrue(valid_lipo_order(commands[0]))


if __name__ == '__main__':
    unittest.main()
