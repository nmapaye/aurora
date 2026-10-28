#!/usr/bin/env python3
"""Keep direct Google OAuth out of the owner-approved Apple-calendar beta."""
import argparse
from pathlib import Path
import plistlib
import sys


def failures(info):
    if not isinstance(info, dict):
        return ["Info.plist must contain a dictionary"]
    errors = [f"{key} is outside this beta's Apple-calendar scope"
              for key in ("AuroraGoogleClientID", "AuroraGoogleCallbackScheme") if key in info]
    types = info.get("CFBundleURLTypes", [])
    if not isinstance(types, list):
        return errors + ["CFBundleURLTypes must be an array"]
    for item in types:
        if not isinstance(item, dict):
            errors.append("Each URL type must be a dictionary")
            continue
        schemes = item.get("CFBundleURLSchemes", [])
        if not isinstance(schemes, list) or any(not isinstance(s, str) for s in schemes):
            errors.append("CFBundleURLSchemes must be an array of strings")
            continue
        if any(s.lower().startswith("com.googleusercontent.apps.") for s in schemes):
            errors.append("Google OAuth callback scheme is outside this beta's scope")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("info_plists", nargs="+", type=Path)
    args = parser.parse_args()
    errors = []
    for path in args.info_plists:
        try:
            info = plistlib.loads(path.read_bytes())
            errors += [f"{path}: {e}" for e in failures(info)]
        except (OSError, ValueError, TypeError, plistlib.InvalidFileException):
            errors.append(f"{path}: could not verify beta scope")
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print(f"Verified Apple-calendar-only beta scope in {len(args.info_plists)} Info.plist files")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
