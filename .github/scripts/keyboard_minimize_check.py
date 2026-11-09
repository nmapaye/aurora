#!/usr/bin/env python3
"""Count real keyboard-minimize events in a `log show --style compact` capture.

BUG-1d (#71) item 1b. The iPad "Check the hardware keyboard is detached" step
used `grep -c 'setMinimized|floating assistant'`, which on run 41957713689
counted two lines that are not a minimize:
  * `-[UIKeyboard setMinimized:] Setting keyboard minimized = 0` (NOT minimized)
  * the probe's own `log show ... --predicate '... setMinimized ...'` command
    line, logged by the `log` process itself.

An entry counts as a minimize event, and fails the check, when it comes from
any process other than the probe's own tooling and is one of:
  * `setMinimized` with `minimized = 1` (or YES/true), or with no readable
    value at all (the bare `-[UIKeyboard setMinimized:]` seen in run
    41378408179's failing iPad Save tap is treated as a minimize);
  * a `visualMode N -> 2` change (2 is the minimized mode: run 41378408179
    logged `visualMode 1 -> 2` with the collapse to the 64 pt Done bar);
  * a floating-assistant presentation (`floating assistant`,
    `undocked + floating`), e.g. InputUI's TUIKeyboardState line.
Ignored, and listed with the reason: `minimized = 0`/NO/false, visualMode
changes to any other mode, and every entry from the probe tooling (`log`,
simctl, xcodebuild, shells) or that quotes the probe's own command text.

Exit 0: no minimize event. Exit 1: at least one. Exit 2: the capture is
missing or is not a compact `log show` capture (never a silent pass).
"""
from __future__ import annotations

import argparse
import dataclasses
import re
import sys
from pathlib import Path
from typing import List, Optional, Sequence

ENTRY = re.compile(
    r"^(?P<ts>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)(?:[+-]\d{4})?\s+(?P<ty>\S+)\s+"
    r"(?P<proc>.+?)\[(?P<pid>\d+):(?P<tid>[0-9a-fA-F]+)\]\s?(?P<msg>.*)$"
)
HEADER = re.compile(r"^Timestamp\s+Ty\s+Process\[PID:TID\]")
# The probe's own tooling: never the app or the keyboard.
TOOL_PROCESSES = {"log", "simctl", "xcodebuild", "bash", "sh", "zsh", "grep", "python3", "Python"}
# Text only the probe's own `log show` invocation contains.
PROBE_TEXT = re.compile(r"log run noninteractively|'--predicate'|--predicate\s|eventMessage CONTAINS")
SET_MINIMIZED = re.compile(r"setMinimized")
MINIMIZED_VALUE = re.compile(r"minimized\s*[=:]\s*(?P<v>\w+)", re.IGNORECASE)
VISUAL_MODE = re.compile(r"visualMode\s+(?P<a>\d+)\s*->\s*(?P<b>\d+)")
MINIMIZED_VISUAL_MODE = "2"
FLOATING = re.compile(r"floating assistant|undocked \+ floating")
NOT_MINIMIZED = {"0", "no", "false"}
MINIMIZED = {"1", "yes", "true"}


@dataclasses.dataclass
class Entry:
    line_no: int
    ts: str
    process: str
    pid: str
    text: str  # header message plus continuation lines


@dataclasses.dataclass
class Finding:
    entry: Entry
    kind: str
    reason: str


@dataclasses.dataclass
class Result:
    events: List[Finding]
    ignored: List[Finding]
    entries: int


class CaptureError(Exception):
    pass


def parse(text: str) -> List[Entry]:
    lines = text.splitlines()
    if not any(HEADER.match(l) for l in lines[:5]):
        raise CaptureError("no `log show --style compact` header (Timestamp Ty Process[PID:TID]) in the first lines")
    entries: List[Entry] = []
    for n, line in enumerate(lines, 1):
        m = ENTRY.match(line)
        if m:
            entries.append(Entry(n, m["ts"], m["proc"].strip(), m["pid"], m["msg"]))
        elif entries:
            entries[-1].text += "\n" + line
    return entries


def classify(entry: Entry) -> Optional[Finding]:
    """Return a Finding (kind 'event' or 'ignored'), or None if unrelated."""
    t = entry.text
    relevant = SET_MINIMIZED.search(t) or VISUAL_MODE.search(t) or FLOATING.search(t)
    if not relevant:
        return None
    if entry.process in TOOL_PROCESSES:
        return Finding(entry, "ignored", f"probe tooling process `{entry.process}`")
    if PROBE_TEXT.search(t):
        return Finding(entry, "ignored", "quotes the probe's own log command")
    if SET_MINIMIZED.search(t):
        v = MINIMIZED_VALUE.search(t.split("setMinimized", 1)[1])
        if v and v["v"].lower() in NOT_MINIMIZED:
            return Finding(entry, "ignored", f"setMinimized with minimized = {v['v']} (not minimized)")
        if v and v["v"].lower() in MINIMIZED:
            return Finding(entry, "event", f"setMinimized with minimized = {v['v']}")
        return Finding(entry, "event", "setMinimized with no readable value (treated as a minimize)")
    vm = VISUAL_MODE.search(t)
    if vm:
        if vm["b"] == MINIMIZED_VISUAL_MODE and vm["a"] != vm["b"]:
            return Finding(entry, "event", f"visualMode {vm['a']} -> {vm['b']} (minimized)")
        return Finding(entry, "ignored", f"visualMode {vm['a']} -> {vm['b']} (not the minimized mode)")
    return Finding(entry, "event", "floating-assistant presentation")


def check(text: str) -> Result:
    entries = parse(text)
    events, ignored = [], []
    for e in entries:
        f = classify(e)
        if f:
            (events if f.kind == "event" else ignored).append(f)
    return Result(events, ignored, len(entries))


def first_line(e: Entry) -> str:
    return f"{e.ts} {e.process}[{e.pid}] {e.text.splitlines()[0][:200]}"


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("capture", type=Path)
    args = ap.parse_args(argv)
    if not args.capture.is_file():
        print(f"keyboard minimize check: {args.capture} is missing")
        return 2
    try:
        r = check(args.capture.read_text(errors="replace"))
    except CaptureError as exc:
        print(f"keyboard minimize check: {args.capture}: {exc}")
        return 2
    print(f"keyboard minimize check: {args.capture}: {r.entries} entries, "
          f"{len(r.events)} minimize event(s), {len(r.ignored)} ignored line(s)")
    for f in r.ignored:
        print(f"  ignored (line {f.entry.line_no}, {f.reason}): {first_line(f.entry)}")
    for f in r.events:
        print(f"  MINIMIZE (line {f.entry.line_no}, {f.reason}): {first_line(f.entry)}")
    return 1 if r.events else 0


if __name__ == "__main__":
    sys.exit(main())
