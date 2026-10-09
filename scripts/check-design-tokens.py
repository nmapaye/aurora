#!/usr/bin/env python3
"""Reject newly introduced brand colors outside the shared SwiftUI theme."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
failures = []
pattern = re.compile(r"\b0x[0-9A-Fa-f]{6}\b|\bColor\(\s*(?:red:|uiColor:\s*UIColor\(hex:)")
for path in (root / "Aurora").rglob("*.swift"):
    if "Theme" in path.parts:
        continue
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if pattern.search(line):
            failures.append(f"{path.relative_to(root)}:{number}: use a semantic Palette token")
print("\n".join(failures) if failures else "Aurora brand-token check passed")
sys.exit(bool(failures))
