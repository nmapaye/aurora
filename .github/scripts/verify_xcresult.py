#!/usr/bin/env python3
"""Reject green xcodebuild receipts that executed no tests or skipped acceptance."""
import argparse
import json
from pathlib import Path
import re
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


def iteration_failures(log, cases, expected):
    """An xcresult can summarize a repeated method once; count actual case ends."""
    errors = []
    for case in cases:
        ends = re.findall(r"^Test [Cc]ase '.* " + re.escape(case) + r"\]' (passed|failed)\b", log, re.MULTILINE)
        passed, failed = ends.count("passed"), ends.count("failed")
        if passed != expected or failed:
            errors.append(f"{case}: expected exactly {expected} passed iterations and no failures; found {passed} passed, {failed} failed")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle")
    parser.add_argument("--iteration-log", type=Path)
    parser.add_argument("--test-case", action="append", default=[])
    parser.add_argument("--expected-iterations", type=int)
    args = parser.parse_args()
    if any((args.iteration_log, args.test_case, args.expected_iterations is not None)):
        if not args.iteration_log or not args.test_case or args.expected_iterations is None or args.expected_iterations <= 0:
            parser.error("iteration verification requires --iteration-log, --test-case and a positive --expected-iterations")
    try:
        result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", args.bundle],
                                check=True, capture_output=True, text=True, timeout=60)
        summary = json.loads(result.stdout)
        errors = failures(summary)
        if args.iteration_log:
            errors += iteration_failures(args.iteration_log.read_text(), args.test_case, args.expected_iterations)
    except (subprocess.SubprocessError, OSError, ValueError, TypeError, AttributeError):
        print("::error::Could not verify the test result bundle")
        return 1
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print(f"Verified {summary['passedTests']} passed tests, zero skips/failures")
        if args.iteration_log:
            print(f"Verified exactly {args.expected_iterations} passed iterations for each of {len(args.test_case)} stress cases")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
