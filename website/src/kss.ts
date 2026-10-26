/**
 * KSS version B anchors from Åkerstedt Miley, Kecklund & Åkerstedt (2016),
 * https://doi.org/10.1007/s41105-016-0048-8 (CC BY 4.0).
 * Sentence capitalization only; no model conversion or clinical inference.
 */
export const KSS_OPTIONS = [
  { value: 1, interpretation: "Extremely alert" },
  { value: 2, interpretation: "Very alert" },
  { value: 3, interpretation: "Alert" },
  { value: 4, interpretation: "Rather alert" },
  { value: 5, interpretation: "Neither alert nor sleepy" },
  { value: 6, interpretation: "Some signs of sleepiness" },
  { value: 7, interpretation: "Sleepy, but no effort to keep awake" },
  { value: 8, interpretation: "Sleepy, some effort to keep awake" },
  {
    value: 9,
    interpretation: "Very sleepy, great effort keeping awake, fighting sleep",
  },
] as const;

export type KssValue = (typeof KSS_OPTIONS)[number]["value"];
export const KSS_LABEL = "Self-reported KSS";

/** Missing or invalid ratings stay absent; never clamp, round, or coerce. */
export function kssRating(value: unknown) {
  return typeof value === "number" && Number.isInteger(value)
    ? (KSS_OPTIONS.find((option) => option.value === value) ?? null)
    : null;
}

/** Only the native select's exact 1–9 option values are accepted. */
export function parseKssSelection(value: string): KssValue | null {
  return value.length === 1 && /^[1-9]$/.test(value)
    ? (kssRating(Number(value))?.value ?? null)
    : null;
}
