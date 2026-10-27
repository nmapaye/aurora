import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile } from "node:fs/promises";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import App, { EnergyCard } from "../node_modules/.cache/aurora-tests/App.js";
import {
  KSS_OPTIONS,
  KSS_LABEL,
  kssRating,
  parseKssSelection,
} from "../src/kss.ts";

// Independent reference table: version B, Åkerstedt Miley et al. (2016).
const anchors = [
  "Extremely alert",
  "Very alert",
  "Alert",
  "Rather alert",
  "Neither alert nor sleepy",
  "Some signs of sleepiness",
  "Sleepy, but no effort to keep awake",
  "Sleepy, some effort to keep awake",
  "Very sleepy, great effort keeping awake, fighting sleep",
];
const card = (props) => renderToStaticMarkup(createElement(EnergyCard, props));

for (let value = 1; value <= 9; value++) {
  test(`KSS ${value} retains the published interpretation and renders on 1–9`, () => {
    const expected = { value, interpretation: anchors[value - 1] };
    assert.deepEqual(kssRating(value), expected);
    assert.equal(parseKssSelection(String(value)), value);
    const html = card({ sleep: "missing", caffeine: "missing", kss: value });
    assert.ok(html.includes(KSS_LABEL));
    assert.ok(html.includes(anchors[value - 1]));
    assert.match(
      html,
      new RegExp(`class="hero-value">${value}<span class="unit"> / 9`),
    );
    assert.equal((html.match(/No record/g) ?? []).length, 2);
  });
}

test("the scale contains exactly the nine distinct integer steps", () => {
  assert.deepEqual(
    KSS_OPTIONS.map((x) => x.value),
    [1, 2, 3, 4, 5, 6, 7, 8, 9],
  );
  assert.equal(new Set(KSS_OPTIONS.map((x) => x.interpretation)).size, 9);
});

test("invalid and missing values are rejected rather than rounded or clamped", () => {
  for (const value of [
    null,
    undefined,
    NaN,
    Infinity,
    -Infinity,
    -1,
    0,
    10,
    100,
    1.5,
    8.9,
    "5",
    "",
    true,
    false,
    {},
    [],
  ]) {
    assert.equal(kssRating(value), null, `Rejected ${String(value)}`);
    const html = card({ sleep: "recorded", caffeine: "recorded", kss: value });
    assert.ok(html.includes("Not rated"));
    assert.ok(!html.includes(" / 9"));
  }
});

test("empty, malformed and out-of-range select input stays unselected", () => {
  for (const value of [
    "",
    " ",
    "0",
    "10",
    "-1",
    "5.5",
    "05",
    "5.0",
    "1e0",
    " 5 ",
    "NaN",
    "Infinity",
    "5x",
    "5\n",
  ]) {
    assert.equal(parseKssSelection(value), null, value);
  }
});

test("sleep and caffeine do not calculate, change or gate a KSS self-rating", () => {
  for (const sleep of ["missing", "recorded"]) {
    for (const caffeine of ["missing", "recorded"]) {
      for (const kss of [null, ...KSS_OPTIONS.map((x) => x.value)]) {
        const html = card({ sleep, caffeine, kss });
        const expected = kss == null ? "Not rated" : anchors[kss - 1];
        assert.ok(html.includes(expected));
        assert.equal(html.includes("7 h 10 m"), sleep === "recorded");
        assert.equal(html.includes("95 mg"), caffeine === "recorded");
        assert.equal(
          (html.match(/No record/g) ?? []).length,
          Number(sleep === "missing") + Number(caffeine === "missing"),
        );
      }
    }
  }
});

test("the page defaults to no rating in both cards and an empty labeled input", () => {
  const html = renderToStaticMarkup(createElement(App));
  assert.equal((html.match(/Not rated/g) ?? []).length, 2);
  assert.equal((html.match(/Self-reported KSS/g) ?? []).length, 2);
  assert.match(html, /<option value="" selected="">Choose your rating/);
  assert.match(html, /<label for="[^"]+">Your sleepiness rating/);
  assert.ok(html.includes("Higher means sleepier."));
  assert.ok(html.includes("Nothing is saved or sent."));
  assert.ok(
    html.includes("does not measure performance or diagnose a condition."),
  );
  assert.ok(html.includes("connect to Apple Health."));
  assert.equal((html.match(/role="switch"/g) ?? []).length, 2);
  assert.equal((html.match(/aria-live="polite"/g) ?? []).length, 1);
  for (const href of [
    "#features",
    "#preview",
    "#release",
    "privacy.html",
    "support.html",
  ]) {
    assert.ok(html.includes(`href="${href}"`));
  }
  assert.ok(html.includes("Clear preview"));
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((x) => x[1]);
  assert.equal(new Set(ids).size, ids.length);
});

test("active website content no longer carries obsolete score or repeated source copy", async () => {
  const html = renderToStaticMarkup(createElement(App));
  for (const phrase of [
    "Estimated alertness",
    "Illustrative number for this page",
    "Source: synthetic values on this page only",
    "/ 100",
    "Estimated KSS",
  ]) {
    assert.ok(!html.toLowerCase().includes(phrase.toLowerCase()), phrase);
  }
  const source = await readFile(
    new URL("../src/App.tsx", import.meta.url),
    "utf8",
  );
  assert.ok(!source.includes("illustrativeScore"));
  assert.ok(!source.includes("demoData"));
});
