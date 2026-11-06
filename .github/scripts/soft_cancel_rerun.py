#!/usr/bin/env python3
"""Run one UI-test step, and rerun it once only for a simulator soft cancel.

BUG-1d (#71), owner-approved Nov 2, 2026. The simulator's synthesized-touch
pipeline sometimes soft-cancels a tap below UIKit: backboardd logs
`touchstats ... soft cancel: 1` and the app's Button gets a cancel instead of
a touch-up, so the tapped action never runs. That is not app behavior.

The rule this script enforces, inside one job:
  * The step may be rerun ONCE, and only when BOTH hold:
      1. the captured backboardd touch log shows a `soft cancel` on the
         failing test's last synthesized tap before its failure, and
      2. that test's failure is the step's only failure (one failed test
         case, one `error:` line, no crash, launch or runner failure).
  * Anything else, or more than one failure, means no rerun.
  * If the rerun fails, the step fails. There is never a third attempt.
  * The log prints that a rerun happened and why: the test, the iteration
    and the matching touchstats line.

Test code still has no retries, extra taps or longer waits; the only retry
lives here, in the workflow. This is not a GitHub "Re-run jobs".
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Optional, Sequence

# The touch/keyboard predicate from BUG-1d item 1a.
LOG_PREDICATE = (
    'eventMessage CONTAINS "setMinimized" OR eventMessage CONTAINS "floating assistant" '
    'OR eventMessage CONTAINS "touchstats" OR eventMessage CONTAINS "BKSHIDKeyboardDevice"'
)
# A soft cancel's touchstats line is logged when the touch ends, about 0.2 s
# after "Synthesize event". Allow a little clock skew before and the touch
# duration plus backboardd's processing after.
WINDOW_BEFORE = 0.5
WINDOW_AFTER = 3.0

CASE_START = re.compile(r"^Test Case '-\[(?P<cls>[\w.]+) (?P<test>\w+)\]' started(?: \(Iteration (?P<it>\d+) of (?P<of>\d+)\))?\.")
CASE_END = re.compile(r"^Test Case '-\[(?P<cls>[\w.]+) (?P<test>\w+)\]' (?P<result>passed|failed|skipped)")
START_AT = re.compile(r"^\s*t =\s+[\d.]+s Start Test at (?P<ts>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(?:\.\d+)?)")
SYNTH = re.compile(r"^\s*t =\s+(?P<t>[\d.]+)s\s+Synthesize event")
ERROR = re.compile(r"^(?P<file>[^:\s][^:]*):(?P<line>\d+): error: -\[(?P<cls>[\w.]+) (?P<test>\w+)\] : (?P<msg>.*)$")
EXECUTED = re.compile(r"Executed (?P<n>\d+) tests?, with (?P<f>\d+) failures? \((?P<u>\d+) unexpected\)")
# Failures that are not one test's missing result: never rerun these.
OTHER_FAILURE = re.compile(
    r"crashed|Restarting after unexpected exit|Early unexpected exit|lost connection|"
    r"Failed to launch|failed to launch|Test runner exited|The test runner hung|"
    r"failed background assertion|Failed to determine hittability|Test crashed",
)
SOFT_CANCEL = re.compile(r"soft cancel:\s*(?P<n>\d+)")
COMPACT_TS = re.compile(r"^(?P<ts>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)(?P<off>[+-]\d{4})?\s+\S+\s+(?P<proc>[^\[\s]+)\[")


@dataclasses.dataclass
class Decision:
    rerun: bool
    reason: str
    test: Optional[str] = None
    iteration: Optional[str] = None
    failure: Optional[str] = None
    tap_time: Optional[str] = None
    touch_line: Optional[str] = None

    def report(self, attempt: int = 1) -> str:
        head = "SOFT-CANCEL RERUN: yes" if self.rerun else "SOFT-CANCEL RERUN: no"
        parts = [f"{head} (attempt {attempt}) - {self.reason}"]
        for label, value in (("test", self.test), ("iteration", self.iteration), ("failure", self.failure),
                             ("failing tap synthesized at", self.tap_time), ("touchstats", self.touch_line)):
            if value:
                parts.append(f"  {label}: {value}")
        return "\n".join(parts)


@dataclasses.dataclass
class _Case:
    test: str
    iteration: str
    start: Optional[dt.datetime] = None
    taps: list = dataclasses.field(default_factory=list)  # (t seconds, line index)
    errors: list = dataclasses.field(default_factory=list)  # (line index, ERROR match)
    failed: bool = False


def _offset(text: str) -> dt.timezone:
    m = re.fullmatch(r"([+-])(\d\d):?(\d\d)", text.strip())
    if not m:
        raise ValueError(f"bad UTC offset {text!r}; want e.g. +0000")
    minutes = int(m.group(2)) * 60 + int(m.group(3))
    return dt.timezone(dt.timedelta(minutes=minutes if m.group(1) == "+" else -minutes))


def _parse_ts(text: str, default_tz: dt.timezone) -> dt.datetime:
    text = text.strip()
    m = re.fullmatch(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(?:\.\d+)?)([+-]\d\d:?\d\d)?", text)
    if not m:
        raise ValueError(f"bad timestamp {text!r}")
    base = m.group(1)
    fmt = "%Y-%m-%d %H:%M:%S.%f" if "." in base else "%Y-%m-%d %H:%M:%S"
    stamp = dt.datetime.strptime(base, fmt)
    return stamp.replace(tzinfo=_offset(m.group(2)) if m.group(2) else default_tz)


def parse_touch_log(text: str, default_tz: dt.timezone) -> list:
    """Returns (time, process, message) entries from `log show` output.

    Accepts `--style ndjson` (one JSON object per line) and `--style compact`
    (continuation lines of a multi-line message are joined to their entry).
    """
    entries = []
    current = None
    for raw in text.splitlines():
        line = raw.rstrip("\n")
        if line.startswith("{"):
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if "timestamp" not in obj or "eventMessage" not in obj:
                continue
            proc = os.path.basename(obj.get("processImagePath") or obj.get("process") or "")
            try:
                when = _parse_ts(obj["timestamp"], default_tz)
            except ValueError:
                continue
            entries.append((when, proc, str(obj["eventMessage"])))
            current = None
            continue
        m = COMPACT_TS.match(line)
        if m:
            when = _parse_ts(m.group("ts") + (m.group("off") or ""), default_tz)
            current = [when, m.group("proc"), line[m.end():]]
            entries.append(current)
        elif current is not None:
            current[2] += " | " + line.strip()
    return [tuple(e) for e in entries]


def _cases(xcodebuild_log: str, default_tz: dt.timezone) -> tuple:
    cases: list = []
    current: Optional[_Case] = None
    errors_outside = 0
    lines = xcodebuild_log.splitlines()
    for index, line in enumerate(lines):
        m = CASE_START.match(line)
        if m:
            it = f"{m.group('it')} of {m.group('of')}" if m.group("it") else "1 of 1"
            current = _Case(test=m.group("test"), iteration=it)
            cases.append(current)
            continue
        if current is not None:
            m = START_AT.match(line)
            if m and current.start is None:
                current.start = _parse_ts(m.group("ts"), default_tz)
                continue
            m = SYNTH.match(line)
            if m:
                current.taps.append((float(m.group("t")), index))
                continue
        m = ERROR.match(line)
        if m:
            if current is not None and m.group("test") == current.test:
                current.errors.append((index, m))
            else:
                errors_outside += 1
            continue
        m = CASE_END.match(line)
        if m and current is not None and m.group("test") == current.test:
            current.failed = m.group("result") == "failed"
            current = None
    return cases, errors_outside, lines


def classify(xcodebuild_log: str, touch_log: str, local_offset: str = "+0000", attempt: int = 1) -> Decision:
    """Decides whether a failed step may be rerun. Pure; no side effects."""
    if attempt != 1:
        return Decision(False, "this was already the rerun; a failed rerun fails the job (no third attempt)")
    tz = _offset(local_offset)
    cases, errors_outside, lines = _cases(xcodebuild_log, tz)
    failed = [c for c in cases if c.failed or c.errors]
    other = sorted({m.group(0) for m in (OTHER_FAILURE.search(l) for l in lines) if m})
    if other:
        return Decision(False, f"the log shows a non-assertion failure ({', '.join(other)})")
    if errors_outside:
        return Decision(False, f"{errors_outside} error line(s) outside a test case")
    if not failed:
        return Decision(False, "no failed test case in the log (build, verify or runner failure)")
    if len(failed) > 1:
        names = ", ".join(f"{c.test} (iteration {c.iteration})" for c in failed)
        return Decision(False, f"{len(failed)} failed test cases, not one: {names}")
    case = failed[0]
    total_errors = len(case.errors)
    summary_failures = [int(m.group("f")) for m in (EXECUTED.search(l) for l in lines) if m]
    if total_errors != 1 or (summary_failures and max(summary_failures) != 1):
        return Decision(False, f"{max([total_errors] + summary_failures)} failures, not exactly one",
                        test=case.test, iteration=case.iteration)
    err_index, err = case.errors[0]
    message = err.group("msg")
    message = message if len(message) <= 160 else message[:157] + "..."
    failure = f"{os.path.basename(err.group('file'))}:{err.group('line')}: {message}"
    taps = [t for t, i in case.taps if i < err_index]
    if case.start is None or not taps:
        return Decision(False, "the failing test has no synthesized tap before its failure",
                        test=case.test, iteration=case.iteration, failure=failure)
    tap = case.start + dt.timedelta(seconds=taps[-1])
    tap_text = tap.astimezone(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3] + "Z"
    entries = parse_touch_log(touch_log, tz)
    if not entries:
        return Decision(False, "no captured touch log, so a soft cancel cannot be shown",
                        test=case.test, iteration=case.iteration, failure=failure, tap_time=tap_text)
    lo = tap - dt.timedelta(seconds=WINDOW_BEFORE)
    hi = tap + dt.timedelta(seconds=WINDOW_AFTER)
    for when, proc, message in entries:
        if "backboardd" not in proc or "touchstats" not in message:
            continue
        m = SOFT_CANCEL.search(message)
        if m and int(m.group("n")) > 0 and lo <= when <= hi:
            line = f"{when.isoformat()} {proc} {' '.join(message.split())}"
            return Decision(True, "backboardd soft-cancelled the failing test's last tap, and it is the step's only failure",
                            test=case.test, iteration=case.iteration, failure=failure, tap_time=tap_text,
                            touch_line=line)
    return Decision(False, "no backboardd soft cancel on the failing tap; a normal failure",
                    test=case.test, iteration=case.iteration, failure=failure, tap_time=tap_text)


# ---------------------------------------------------------------------------
# Step runner


Runner = Callable[[Sequence[str], Optional[Path]], int]


def _run(cmd: Sequence[str], log: Optional[Path]) -> int:
    try:
        if log is None:
            return subprocess.call(list(cmd))
        with open(log, "w") as out:
            return subprocess.call(list(cmd), stdout=out, stderr=subprocess.STDOUT)
    except OSError as error:
        print(f"could not run {cmd[0]}: {error}", file=sys.stderr)
        return 127


def attempt_paths(log: Path, result: Path, attempt: int) -> tuple:
    if attempt == 1:
        return log, result
    return log.with_name(f"{log.stem}-rerun{log.suffix}"), result.with_name(f"{result.stem}-Rerun{result.suffix}")


def capture_touch_log(udid: str, out: Path, seconds: float, runner: Runner = _run) -> None:
    minutes = int(seconds // 60) + 2
    cmd = ["xcrun", "simctl", "spawn", udid, "log", "show", "--style", "ndjson",
           "--last", f"{minutes}m", "--predicate", LOG_PREDICATE]
    runner(cmd, out)


def run_step(command: Sequence[str], log: Path, result: Path, verify: Sequence[str], udid: str,
             touch_log_base: Path, local_offset: str, runner: Runner = _run,
             capture: Callable[[str, Path, float], None] = None, clock: Callable[[], float] = time.time,
             emit: Callable[[str], None] = print) -> int:
    capture = capture or (lambda u, o, s: capture_touch_log(u, o, s, runner))
    started = clock()
    status = 1
    for attempt in (1, 2):
        attempt_log, attempt_result = attempt_paths(log, result, attempt)
        status = runner(list(command) + ["-resultBundlePath", str(attempt_result)], attempt_log)
        if status == 0 and verify:
            args = [a.replace("{log}", str(attempt_log)).replace("{result}", str(attempt_result)) for a in verify]
            status = runner(args, None)
        if status == 0:
            if attempt == 2:
                emit(f"::warning title=soft-cancel rerun::the rerun passed; attempt 1 is in {log}")
            return 0
        touch = touch_log_base.with_name(f"{touch_log_base.name}-attempt{attempt}.ndjson")
        capture(udid, touch, clock() - started)
        xlog = attempt_log.read_text(errors="replace") if attempt_log.exists() else ""
        tlog = touch.read_text(errors="replace") if touch.exists() else ""
        decision = classify(xlog, tlog, local_offset, attempt)
        emit(decision.report(attempt))
        if not decision.rerun:
            return status
        emit(f"::warning title=soft-cancel rerun::rerunning this step once: {decision.test} "
             f"iteration {decision.iteration} failed after a backboardd soft cancel: {decision.touch_line}")
    return status


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("classify", help="decide from saved logs")
    c.add_argument("--xcodebuild-log", required=True, type=Path)
    c.add_argument("--touch-log", required=True, type=Path)
    c.add_argument("--local-offset", default="+0000")
    c.add_argument("--attempt", type=int, default=1)
    r = sub.add_parser("run", help="run a step, rerunning once only for a soft cancel")
    r.add_argument("--log", required=True, type=Path)
    r.add_argument("--result", required=True, type=Path)
    r.add_argument("--verify", default="", help="verify command; {log} and {result} are substituted")
    r.add_argument("--udid", required=True)
    r.add_argument("--touch-log", required=True, type=Path, help="base path for keyboard-mode ndjson captures")
    r.add_argument("--local-offset", default=dt.datetime.now().astimezone().strftime("%z"))
    r.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.cmd == "classify":
        xlog = args.xcodebuild_log.read_text(errors="replace")
        tlog = args.touch_log.read_text(errors="replace") if args.touch_log.exists() else ""
        decision = classify(xlog, tlog, args.local_offset, args.attempt)
        print(decision.report(args.attempt))
        return 0 if decision.rerun else 1
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("run needs a command after --")
    return run_step(command, args.log, args.result, shlex.split(args.verify), args.udid, args.touch_log,
                    args.local_offset)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
