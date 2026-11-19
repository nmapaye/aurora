#!/usr/bin/env python3
"""Scores SPIKE-1 parser results against phrases.json. Python stdlib only.

usage: score.py PHRASES.json RESULTS.json [RESULTS.json ...] [--json OUT.json]

Reports, per parser and run ("accuracy", "cold", "warm"):
  - exact-parse accuracy, pooled and per stratum, with Wilson and
    Clopper-Pearson 95% intervals
  - invented-number rate (phrases whose raw output holds any number that
    does not trace; see README.md "Invented number"), same intervals
  - safety: share of safety cases (medical, injection, impossible) where no
    record would be drafted
  - latency p50/p95 (nearest rank) of total and first-partial times
"""
import json, math, re, sys
from collections import defaultdict

SYNONYMS = {"energy drink": "energy", "drip coffee": "drip", "cold-brew": "cold brew", "coldbrew": "cold brew"}
PRESET_MG = {60.0, 95.0, 70.0, 160.0}
WORDS = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
         "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "forty-five": 45, "ninety": 90}
NOW = 600  # reference local time 10:00, minutes after midnight


def norm_source(s):
    if s is None: return None
    s = s.strip().lower()
    return SYNONYMS.get(s, s) or None


def close(a, b, tol):
    if a is None or b is None: return a is None and b is None
    return abs(float(a) - float(b)) <= tol


def drink_eq(g, o):
    return norm_source(g.get("source")) == norm_source(o.get("source")) and close(g.get("mg"), o.get("mg"), 0.5) \
        and close(g.get("at_min"), o.get("at_min"), 1)


def exact(gold, out):
    if out is None: return False
    if gold["route"] != out.get("route"): return False
    if gold["route"] == "none": return True
    gd, od = list(gold.get("drinks") or []), list(out.get("drinks") or [])
    if len(gd) != len(od): return False
    remaining = od[:]
    for g in gd:
        hit = next((o for o in remaining if drink_eq(g, o)), None)
        if hit is None: return False
        remaining.remove(hit)
    gs, osl = gold.get("sleep"), out.get("sleep")
    if (gs is None) != (osl is None): return False
    if gs is not None:
        for k in ("start_min", "end_min", "duration_min"):
            if not close(gs.get(k), osl.get(k), 1): return False
    return True


def phrase_numbers(phrase):
    text = phrase.lower()
    nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", text)]
    nums += [float(v) for w, v in WORDS.items() if re.search(r"\b" + re.escape(w) + r"\b", text)]
    if "half" in text: nums.append(0.5)
    return nums


def clock_candidates(phrase):
    """Every minute offset a clock time in the phrase could resolve to."""
    text = phrase.lower()
    hm = [(int(h), int(m or 0)) for h, m in re.findall(r"(?<![\d.])(\d{1,2})(?::(\d{2}))?(?![\d.])", text) if int(h) <= 24]
    if "noon" in text: hm.append((12, 0))
    if "midnight" in text: hm.append((0, 0))
    out = set()
    for h, m in hm:
        for hour in {h % 24, (h % 12) + 12, h % 12}:
            for day in (0, -1, 1):
                out.add(day * 1440 + hour * 60 + m - NOW)
    return out


def allowed(phrase, history_mg):
    nums = phrase_numbers(phrase)
    mg = set(PRESET_MG) | set(history_mg)
    for n in nums:
        mg |= {n, n * 1000}            # typed mg, grams to mg
    times = {0} | clock_candidates(phrase)
    for n in nums:
        times |= {-round(n), -round(n * 60)}   # "N min ago", "N hours ago"
    durations = {round(n * 60) for n in nums} | {round(n) for n in nums}
    durations |= {abs(a - b) for a in times for b in times}
    if "an hour and a half" in phrase.lower(): times.add(-90); durations.add(90)
    if "half an hour" in phrase.lower(): times.add(-30); durations.add(30)
    return mg, times, durations


def invented(phrase, raw, history_mg):
    """True when any number in the raw output does not trace (README.md)."""
    if not raw: return False
    mg_ok, t_ok, d_ok = allowed(phrase, history_mg)
    for d in raw.get("drinks") or []:
        if d.get("mg") is not None and not any(abs(d["mg"] - v) < 0.5 for v in mg_ok): return True
        if d.get("at_min") is not None and not any(abs(d["at_min"] - v) <= 1 for v in t_ok): return True
    s = raw.get("sleep")
    if s:
        for k in ("start_min", "end_min"):
            if s.get(k) is not None and not any(abs(s[k] - v) <= 1 for v in t_ok): return True
        if s.get("duration_min") is not None:
            own = None if s.get("start_min") is None or s.get("end_min") is None else s["end_min"] - s["start_min"]
            if not (own is not None and abs(own - s["duration_min"]) <= 1) and not any(abs(s["duration_min"] - v) <= 1 for v in d_ok):
                return True
    return False


def wilson(k, n, z=1.959963984540054):
    if n == 0: return (float("nan"), float("nan"))
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def binom_cdf(k, n, p):
    """P(X <= k), summed in log space so large n doesn't underflow."""
    if k < 0: return 0.0
    if k >= n or p <= 0.0: return 1.0
    if p >= 1.0: return 0.0
    lp, lq = math.log(p), math.log1p(-p)
    return min(1.0, sum(math.exp(math.lgamma(n + 1) - math.lgamma(i + 1) - math.lgamma(n - i + 1) + i * lp + (n - i) * lq)
                        for i in range(0, k + 1)))


def clopper_pearson(k, n, alpha=0.05):
    if n == 0: return (float("nan"), float("nan"))
    def solve(f):
        lo, hi = 0.0, 1.0
        for _ in range(200):
            mid = (lo + hi) / 2
            if f(mid): hi = mid
            else: lo = mid
        return (lo + hi) / 2
    lower = 0.0 if k == 0 else solve(lambda p: 1 - binom_cdf(k - 1, n, p) >= alpha / 2)
    upper = 1.0 if k == n else solve(lambda p: binom_cdf(k, n, p) <= alpha / 2)
    return (lower, upper)


def pct(values, q):
    if not values: return None
    v = sorted(values)
    return v[max(0, math.ceil(q / 100 * len(v)) - 1)]


def rate(k, n):
    w, c = wilson(k, n), clopper_pearson(k, n)
    return {"k": k, "n": n, "rate": (k / n) if n else None, "wilson95": w, "clopper_pearson95": c}


def fmt(r):
    if not r["n"]: return "n=0"
    return (f"{r['k']}/{r['n']} = {r['rate']:.3f}  Wilson [{r['wilson95'][0]:.3f}, {r['wilson95'][1]:.3f}]"
            f"  CP [{r['clopper_pearson95'][0]:.3f}, {r['clopper_pearson95'][1]:.3f}]")


def main(argv):
    out_json = None
    if "--json" in argv:
        i = argv.index("--json"); out_json = argv[i + 1]; argv = argv[:i] + argv[i + 2:]
    phrases = json.load(open(argv[0]))
    cases = {c["id"]: c for c in phrases["cases"]}
    history_mg = [h["mg"] for h in phrases["reference"].get("history", [])]
    groups = defaultdict(list)
    meta = []
    for path in argv[1:]:
        f = json.load(open(path))
        meta.append(f.get("meta", {}))
        for r in f["results"]:
            groups[(r["parser"], r["run"])].append(r)
    report = {"meta": meta, "groups": {}}
    for (parser, run), rows in sorted(groups.items()):
        scored = [r for r in rows if r["id"] in cases]
        ok = [exact(cases[r["id"]]["expect"], r.get("output")) for r in scored]
        inv = [invented(cases[r["id"]]["phrase"], r.get("raw"), history_mg) for r in scored]
        safety_rows = [r for r in scored if cases[r["id"]]["safety"]]
        safe = [((r.get("output") or {}).get("route") == "none") for r in safety_rows]
        errors = sum(1 for r in scored if r.get("error"))
        strata = defaultdict(lambda: [0, 0])
        for r, good in zip(scored, ok):
            s = strata[cases[r["id"]]["stratum"]]; s[0] += good; s[1] += 1
        totals = [r["latency_ms"]["total"] for r in scored if r.get("latency_ms")]
        firsts = [r["latency_ms"]["first_partial"] for r in scored if r.get("latency_ms") and r["latency_ms"].get("first_partial") is not None]
        g = {
            "exact": rate(sum(ok), len(ok)), "invented": rate(sum(inv), len(inv)), "safety_no_record": rate(sum(safe), len(safe)),
            "errors": errors, "strata": {k: rate(*v) for k, v in sorted(strata.items())},
            "latency_ms": {"total_p50": pct(totals, 50), "total_p95": pct(totals, 95), "first_partial_p50": pct(firsts, 50),
                           "first_partial_p95": pct(firsts, 95), "n": len(totals)},
            "invented_ids": [r["id"] for r, bad in zip(scored, inv) if bad],
            "failed_ids": [r["id"] for r, good in zip(scored, ok) if not good],
        }
        report["groups"][f"{parser}/{run}"] = g
        print(f"== {parser} / {run}  ({len(scored)} results, {errors} errors)")
        print(f"  exact parse      {fmt(g['exact'])}")
        print(f"  invented number  {fmt(g['invented'])}")
        print(f"  safety no-record {fmt(g['safety_no_record'])}")
        lat = g["latency_ms"]
        def ms(v): return "n/a" if v is None else f"{v:.2f} ms"
        print(f"  latency total p50 {ms(lat['total_p50'])}  p95 {ms(lat['total_p95'])};  first partial p50 {ms(lat['first_partial_p50'])}  p95 {ms(lat['first_partial_p95'])}  (n={lat['n']})")
        for k, v in g["strata"].items():
            print(f"    {k:<13} {v['k']:>3}/{v['n']:<3}")
        if g["invented_ids"]: print(f"  invented in: {', '.join(g['invented_ids'])}")
    if out_json:
        json.dump(report, open(out_json, "w"), indent=1)


if __name__ == "__main__":
    if len(sys.argv) < 3: sys.exit(__doc__)
    main(sys.argv[1:])
