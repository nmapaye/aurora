#!/usr/bin/env python3
"""Require executed CI checks for the exact commit before signing or uploading."""
import argparse
import json
import re
import subprocess
import sys

REQUIRED = (
    "Swift Core gate", "swift-core (Linux)", "swift-core (macOS)",
    "iOS App gate", "ios-app (iPhone)", "ios-app (iPad)",
    "gitleaks", "Analyze (actions)", "Analyze (javascript-typescript)", "Analyze (swift)",
    "privacy manifest", "Release safety", "Website build",
)


def failures(pages, sha):
    checks = [check for page in pages for check in page["check_runs"]]
    errors = []
    for name in REQUIRED:
        matches = [c for c in checks if c.get("name") == name
                   and c.get("head_sha") == sha
                   and c.get("app", {}).get("id") == 15368]
        if len(matches) != 1:
            errors.append(f"{name}: expected one GitHub Actions check for this commit, found {len(matches)}")
        elif matches[0].get("status") != "completed" or matches[0].get("conclusion") != "success":
            errors.append(f"{name}: {matches[0].get('status')}/{matches[0].get('conclusion')}; executed success required")
    return errors


def reporting_failures(settings):
    return [] if settings.get("enabled") is True else ["Private vulnerability reporting is disabled or unverified; enable the documented private channel before beta"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--sha", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository) or not re.fullmatch(r"[0-9a-f]{40}", args.sha):
        parser.error("expected owner/repository and a full lowercase commit SHA")
    endpoint = f"repos/{args.repository}/commits/{args.sha}/check-runs?filter=latest&per_page=100"
    try:
        result = subprocess.run(["gh", "api", "--method", "GET", "--paginate", "--slurp", endpoint],
                                check=True, capture_output=True, text=True, timeout=60)
        errors = failures(json.loads(result.stdout), args.sha)
        reporting = subprocess.run(["gh", "api", "--method", "GET", f"repos/{args.repository}/private-vulnerability-reporting"],
                                   check=True, capture_output=True, text=True, timeout=60)
        errors += reporting_failures(json.loads(reporting.stdout))
    except (subprocess.SubprocessError, OSError, ValueError, KeyError, TypeError):
        # Do not print provider output: failure diagnostics need no credentials.
        print("::error::Could not verify release checks; signing and upload remain blocked")
        return 1
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print(f"All {len(REQUIRED)} mandatory checks executed successfully for {args.sha}")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
