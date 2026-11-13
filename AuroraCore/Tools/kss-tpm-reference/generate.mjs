// Writes Tests/AuroraCoreTests/Fixtures/kss-tpm-ts-reference.json by running
// the existing TypeScript research reproduction (website/research/tpm-kss.ts)
// on identical inputs. The Swift KSSModel must match these outputs.
// Synthetic mathematical cases, NOT human KSS observations.
//
//   node AuroraCore/Tools/kss-tpm-reference/generate.mjs   (Node >= 23.6)
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

const tsUrl = new URL("../../../website/research/tpm-kss.ts", import.meta.url);
const outUrl = new URL("../../Tests/AuroraCoreTests/Fixtures/kss-tpm-ts-reference.json", import.meta.url);
const { evaluateResearchBaseline, TPM } = await import(tsUrl.href);
const tsSha256 = createHash("sha256").update(await readFile(tsUrl)).digest("hex");

const H = 3_600_000;
const none = { complete: true, doses: [] };
function timeline(startMs, plan) {
  const history = [];
  let t = startMs;
  for (const [state, hours] of plan) {
    if (!hours) continue;
    history.push({ state, start: t, end: t + hours * H });
    t += hours * H;
  }
  return { history, at: t };
}
const cases = [];
function add(name, { start, plan, timeZone = "UTC", phaseHours = 16.8, caffeine = none, at, mutate }) {
  const built = timeline(start, plan);
  const input = { at: at ?? built.at, timeZone, phaseHours, history: built.history, caffeine };
  if (mutate) mutate(input);
  const r = evaluateResearchBaseline(input);
  cases.push({
    name,
    input,
    expected: r.status === "research-baseline-only"
      ? { status: r.status, rawKss: r.rawKss, boundedKss: r.boundedKss, hoursAwake: r.hoursAwake, ...r.components }
      : { status: r.status, reason: r.reason },
  });
}

const utc = Date.UTC(2026, 9, 20, 23); // Tue Oct 20 2026 23:00 UTC
const la = Date.UTC(2026, 9, 21, 6); // Oct 20 2026 23:00 PDT
const laDst = Date.UTC(2026, 9, 31, 6); // Oct 30 23:00 PDT; DST ends Sun Nov 1 02:00
for (const d of [4, 6, 8, 10]) for (const w of [0, 4, 12, 16])
  add(`UTC ${d}h sleep then ${w}h awake`, { start: utc, plan: [["sleep", 8], ["awake", 16], ["sleep", d], ["awake", w]] });
for (const p of [15, 18.5]) add(`UTC phase ${p}h, 8h sleep, 6h awake`, { start: utc, phaseHours: p, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 6]] });
for (const w of [0.25, 2, 9]) add(`Los Angeles 7.5h sleep then ${w}h awake`, { timeZone: "America/Los_Angeles", start: la, plan: [["sleep", 7], ["awake", 17], ["sleep", 7.5], ["awake", w]] });
add("Fragmented night: 3h sleep, 40 min awake, 4h sleep, 2h awake", { start: utc, plan: [["sleep", 8], ["awake", 16], ["sleep", 3], ["awake", 2 / 3], ["sleep", 4], ["awake", 2]] });
add("Highly fragmented: six 1h sleeps with 15 min awakenings", { start: utc, plan: [["sleep", 8], ["awake", 16], ...Array.from({ length: 6 }, (_, i) => [["sleep", 1], ["awake", i === 5 ? 3 : 0.25]]).flat()] });
add("Nap: 20 min nap after 6h awake, then 1h awake", { start: utc, plan: [["sleep", 8], ["awake", 16], ["sleep", 7], ["awake", 6], ["sleep", 1 / 3], ["awake", 1]] });
add("Deep debt below brake: 36h awake, 2h sleep, 3h awake", { start: utc, plan: [["sleep", 8], ["awake", 36], ["sleep", 2], ["awake", 3]] });
add("Three nights, 5h each", { start: utc, plan: [["sleep", 5], ["awake", 19], ["sleep", 5], ["awake", 19], ["sleep", 5], ["awake", 5]] });
add("DST fall-back night in Los Angeles, 8h sleep then 4h awake", { timeZone: "America/Los_Angeles", start: laDst, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 4]] });
add("Zero-mg caffeine record is allowed", { start: utc, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 3]], caffeine: { complete: true, doses: [{ at: utc + 33 * H, mg: 0 }] } });
// Refusals
add("Refuse: no sleep data", { start: utc, plan: [], at: utc + 30 * H });
add("Refuse: only one sleep episode", { start: utc, plan: [["sleep", 8], ["awake", 4]] });
add("Refuse: first segment awake", { start: utc, plan: [["awake", 2], ["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 2]] });
add("Refuse: unknown interval", { start: utc, plan: [["sleep", 8], ["unknown", 16], ["sleep", 8], ["awake", 2]] });
add("Refuse: gap between records", { start: utc, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 2]], mutate: (i) => { i.history[1].end -= H; } });
add("Refuse: split episode (two adjacent sleeps)", { start: utc, plan: [["sleep", 8], ["awake", 16], ["sleep", 4], ["awake", 0]], mutate: (i) => { const s = i.history[2]; i.history.push({ state: "sleep", start: s.end, end: s.end + H }); i.at = s.end + H; } });
add("Refuse: more than 16h awake", { start: utc, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 17]] });
add("Refuse: record ends after query", { start: utc, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 2]], mutate: (i) => { i.at -= 1; } });
add("Refuse: phase out of range", { start: utc, phaseHours: 24, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 2]] });
add("Refuse: caffeine history unknown", { start: utc, caffeine: null, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 2]] });
add("Refuse: caffeine history incomplete", { start: utc, caffeine: { complete: false, doses: [] }, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 2]] });
add("Refuse: 95 mg coffee is not modeled", { start: utc, caffeine: { complete: true, doses: [{ at: utc + 33 * H, mg: 95 }] }, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 2]] });
add("Refuse: negative caffeine dose", { start: utc, caffeine: { complete: true, doses: [{ at: utc + 33 * H, mg: -5 }] }, plan: [["sleep", 8], ["awake", 16], ["sleep", 8], ["awake", 2]] });

await writeFile(outUrl, JSON.stringify({
  kind: "TypeScript tpm-kss.ts outputs on synthetic inputs; NOT human KSS observations",
  source: "Ingre et al. 2014, DOI 10.1371/journal.pone.0108679, eqs 1.1-1.9 (original full TPM)",
  generator: "AuroraCore/Tools/kss-tpm-reference/generate.mjs",
  tsFile: "website/research/tpm-kss.ts",
  tsSha256,
  tsParameters: TPM,
  cases,
}, null, 2) + "\n");
console.log(`Wrote ${cases.length} cases (tpm-kss.ts sha256 ${tsSha256}).`);
