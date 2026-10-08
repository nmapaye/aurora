#!/usr/bin/env python3
"""Synthetic, opt-in local inference check. Never sends health/calendar records."""
import argparse
import json
import pathlib
import time
import urllib.request

CASES = [
    ("Can you help me make sense of my sluggishness today?", "explainEnergy"),
    ("Please record an espresso I just finished", "logCaffeine"),
    ("Could I see the pattern of my caffeine records over the last seven days?", "weeklyTrends"),
    ("Can you review my upcoming commitments?", "calendar"),
    ("I want to record my night of sleep", "logSleep"),
    ("Open my previous entries", "history"),
    ("I'd like to measure my reaction speed", "reactionTest"),
    ("How much caffeine should I drink to stay awake?", "unsupported"),
    ("Please tell me what medication to take", "unsupported"),
    ("Write a poem about the moon", "unsupported"),
    ("Could you give me an overview of today?", "briefing"),
    ("Share my recorded data as CSV", "exports"),
    ("Let me manage my cutoff notification", "reminders"),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="gemma4:26b")
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    if "cloud" in args.model.lower():
        parser.error("Cloud models are not accepted")
    show = urllib.request.Request("http://127.0.0.1:11434/api/show",
        data=json.dumps({"model": args.model}).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(show, timeout=10) as response:
        metadata = json.load(response)
    if metadata.get("remote_host") or metadata.get("remote_model") or not metadata.get("model_info"):
        parser.error("Select an installed local model with local weights")
    root = pathlib.Path(__file__).resolve().parents[1]
    source = (root / "AuroraCore/Sources/AuroraCore/Assistant.swift").read_text()
    instructions = source.split('public static let modelInstructions = """', 1)[1].split('"""', 1)[0]
    results = []
    for prompt, expected in CASES:
        started = time.monotonic()
        body = {"model": args.model, "messages": [
            {"role": "system", "content": instructions}, {"role": "user", "content": prompt}],
            "stream": False, "think": False, "options": {"temperature": 0, "num_predict": 40}}
        request = urllib.request.Request("http://127.0.0.1:11434/api/chat",
            data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=45) as response:
            output = json.load(response).get("message", {}).get("content", "").strip()
        result = {"input": prompt, "expected": expected, "actual": output,
            "passed": output == expected, "seconds": round(time.monotonic() - started, 3)}
        results.append(result)
        print(json.dumps(result), flush=True)
    report = {"model": args.model, "passed": sum(x["passed"] for x in results), "total": len(results), "cases": results}
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    raise SystemExit(0 if report["passed"] == report["total"] else 1)


if __name__ == "__main__":
    main()
