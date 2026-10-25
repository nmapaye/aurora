#!/usr/bin/env python3
"""Reject green xcodebuild receipts that executed no tests or skipped acceptance."""
import argparse
import json
import subprocess
import sys


def failures(summary):
    keys = ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")
    if any(type(summary.get(k)) is not int for k in keys):
        return ["Result summary is missing test counts"]
    if summary["totalTestCount"] <= 0:
        return ["No tests executed; check the scheme and test identifier filters"]
    if summary.get("result") != "Passed" or summary["passedTests"] != summary["totalTestCount"]:
        return ["Not every selected test passed"]
    if any(summary[k] != 0 for k in ("failedTests", "skippedTests", "expectedFailures")):
        return ["Failures, skips or expected failures cannot satisfy beta acceptance"]
    return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle")
    args = parser.parse_args()
    try:
        result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", args.bundle],
                                check=True, capture_output=True, text=True, timeout=60)
        summary = json.loads(result.stdout)
        errors = failures(summary)
    except (subprocess.SubprocessError, OSError, ValueError, TypeError, AttributeError):
        print("::error::Could not verify the test result bundle")
        return 1
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print(f"Verified {summary['passedTests']} passed tests, zero skips/failures")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
