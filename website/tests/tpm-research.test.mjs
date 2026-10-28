import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  TPM,
  wakeState,
  originalSleepState,
  sleepState,
  clockTerms,
  evaluateResearchBaseline,
} from "../research/tpm-kss.ts";
const reference = JSON.parse(
  await readFile(
    new URL("../research/fixtures/tpm-reference.json", import.meta.url),
    "utf8",
  ),
);
const valid = () =>
  structuredClone(
    reference.cases.find((c) => c.name === "8h sleep then 4h awake").input,
  );
function near(a, b, tolerance = 3e-7) {
  assert.ok(Math.abs(a - b) <= tolerance, `${a} differs from ${b}`);
}

for (const fixture of reference.cases) {
  test(`TPM equation reproduction: ${fixture.name}`, () => {
    const result = evaluateResearchBaseline(fixture.input);
    assert.equal(result.status, "research-baseline-only");
    near(result.rawKss, fixture.expected.rawKss);
    for (const key of ["homeostatic", "circadian", "ultradian", "inertia"]) {
      near(result.components[key], fixture.expected[key]);
    }
    assert.ok(result.boundedKss >= 1 && result.boundedKss <= 9);
    assert.match(
      result.validation,
      /no independent clinical or caffeine validation/,
    );
  });
}

test("published original sleep recovery calibration: 7.96 to 14.0 in eight hours", () => {
  near(originalSleepState(7.96, 8), 14, 1e-12);
  near(originalSleepState(TPM.upper, 8), TPM.upper, 1e-12);
});

test("homeostatic propagation has continuous brake and physiological asymptotes", () => {
  const start = 8,
    at =
      (TPM.brakeLevel - start) / (TPM.sleepRate * (TPM.brakeLevel - TPM.upper));
  near(sleepState(start, at), 12.2, 1e-12);
  assert.ok(sleepState(start, at - 1e-6) < 12.2);
  assert.ok(sleepState(start, at + 1e-6) > 12.2);
  near(sleepState(start, 1000), 14.3, 1e-12);
  near(wakeState(14, 1000), 2.4, 1e-12);
  assert.ok(sleepState(start, 8) > sleepState(start, 4));
  assert.ok(wakeState(14, 16) < wakeState(14, 4));
  for (const fn of [sleepState, originalSleepState, wakeState]) {
    for (const [level, hours] of [
      [NaN, 1],
      [14.4, 1],
      [2.3, 1],
      [8, -1],
      [8, Infinity],
    ]) {
      assert.throws(() => fn(level, hours), RangeError);
    }
  }
});

test("published clock phases include the ultradian three-hour offset", () => {
  near(clockTerms(16.8, 16.8).circadian, 2.5, 1e-12);
  near(clockTerms(19.8, 16.8).ultradian, 0, 1e-12);
  near(clockTerms(25.8, 16.8).ultradian, -1, 1e-12);
  near(clockTerms(16.8 + 24, 16.8).circadian, 2.5, 1e-12);
});

test("unknown coverage, gaps, overlap, partial history and future records block output", () => {
  const check = (change, reason) => {
    const input = valid();
    change(input);
    assert.deepEqual(evaluateResearchBaseline(input), {
      status: "not-supported",
      reason,
    });
  };
  check((x) => (x.history = []), "missing-sleep-history");
  check((x) => (x.history[1].state = "unknown"), "unknown-sleep-wake-state");
  check((x) => (x.history[1].start += 1), "gap-or-overlap");
  check((x) => (x.history[1].start -= 1), "gap-or-overlap");
  check((x) => (x.history = x.history.slice(1)), "incomplete-history");
  check((x) => (x.history = x.history.slice(0, 2)), "incomplete-history");
  check((x) => (x.history[3].end += 1), "invalid-history");
  check((x) => (x.history[0].end = x.history[0].start), "invalid-history");
  check((x) => (x.history[0].state = "awake"), "split-episode");
  check((x) => (x.phaseHours = NaN), "invalid-query");
  check((x) => (x.phaseHours = 24), "invalid-query");
  check((x) => (x.timeZone = undefined), "invalid-time-zone");
  check((x) => (x.timeZone = "invalid/zone"), "invalid-time-zone");
  check((x) => {
    x.history[3].end = x.at += 13 * 3600000;
  }, "outside-study-wake-window");
  const twoSegments = valid();
  twoSegments.history = twoSegments.history.slice(2);
  assert.equal(
    evaluateResearchBaseline(twoSegments).reason,
    "needs-two-sleep-episodes",
  );
});

test("a 95 mg coffee never gets a fabricated KSS adjustment", () => {
  const input = valid();
  input.caffeine.doses = [{ at: input.at - 3600000, mg: 95 }];
  assert.deepEqual(evaluateResearchBaseline(input), {
    status: "not-supported",
    reason: "caffeine-effect-not-validated",
  });
  input.caffeine = null;
  assert.equal(
    evaluateResearchBaseline(input).reason,
    "unknown-caffeine-history",
  );
  input.caffeine = { complete: false, doses: [] };
  assert.equal(
    evaluateResearchBaseline(input).reason,
    "unknown-caffeine-history",
  );
  input.caffeine = { complete: true, doses: [{ at: input.at + 1, mg: 95 }] };
  assert.equal(
    evaluateResearchBaseline(input).reason,
    "invalid-caffeine-history",
  );
  input.caffeine.doses = [{ at: input.at, mg: -1 }];
  assert.equal(
    evaluateResearchBaseline(input).reason,
    "invalid-caffeine-history",
  );
});

test("DST repeated clock times retain true elapsed wake duration", () => {
  const a = valid();
  const target = Date.parse("2026-11-01T05:30:00Z");
  const offset = target - a.at;
  a.at += offset;
  for (const s of a.history) {
    s.start += offset;
    s.end += offset;
  }
  a.timeZone = "America/New_York";
  const b = structuredClone(a);
  b.at += 3600000;
  b.history.at(-1).end += 3600000;
  const ra = evaluateResearchBaseline(a),
    rb = evaluateResearchBaseline(b);
  assert.equal(ra.status, "research-baseline-only");
  assert.equal(rb.status, "research-baseline-only");
  near(rb.hoursAwake - ra.hoursAwake, 1, 1e-12);
  near(ra.components.circadian, rb.components.circadian, 1e-12);
  assert.notEqual(ra.components.homeostatic, rb.components.homeostatic);
});

test("research implementation stays out of the marketing entry points", async () => {
  for (const path of ["../src/main.tsx", "../src/App.tsx"]) {
    const source = await readFile(new URL(path, import.meta.url), "utf8");
    assert.ok(!source.includes("tpm-kss"));
    assert.ok(!source.includes("evaluateResearchBaseline"));
  }
});
