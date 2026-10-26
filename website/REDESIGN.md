# Aurora website redesign — October 26, 2026

Implemented in `nmapaye-bot/aurora-website-brand`, based on verified `origin/main`
`b9887ac9`. The original checkout was `main` at `a59e6486` with unrelated
untracked .expo/, ios/, and HANDOFF-2026-10-13.md; those remain unchanged.

## Audit and sources

Compared https://nmapaye.com and https://aurora.nmapaye.com in the live browser,
read their served HTML and Aurora's served CSS, and inspected both repositories.
Portfolio reference: `/Users/nmapaye/Documents/Local Coding Projects/nmapaye-site`,
commit `0791070`, especially tokens.css, global.css, Hero.astro and Nav.astro.
Aurora source: website/src/App.tsx, styles.css, and public policy/support pages.

| Inconsistency | Implementation |
| --- | --- |
| Portfolio's yellow/ink editorial palette versus live Aurora's blue gradients | Shared exact ink #101010, paper #f7f5ee, white and yellow #ffeb09 |
| Condensed portfolio headlines versus generic system display type | Self-hosted Barlow Condensed Extra Bold; Space Grotesk matches the portfolio body face |
| Heavy rules and square controls versus pills and soft panels | Ruled feature rows, square buttons/switches, clear section boundaries |
| Weak connection to the developer | Visible attribution, portfolio link, matching footer and navigation grammar |
| Privacy and support looked unrelated to either site | Shared brand.css, reading layout, font assets and focus treatment |

The live Aurora site predates the current repository: its four-screen simulator
contains retired dosing/sleep recommendations and unavailable release-link
placeholders. This implementation retains the current repository's supported
two-switch synthetic evidence preview and current product/privacy copy instead
of reintroducing those obsolete claims. The live site and current website source
contain no app screenshot assets. The hero's native-style illustration is explicitly
labeled synthetic and is not presented as an app screenshot. The original wave
SVG, app source, native palette and project configuration are unchanged.

## Implementation

- Reusable site primitives in public/brand.css, shared by all three pages.
- Responsive website layout in src/styles.css; website-only design system in
  DESIGN.md and .impeccable/design.json, with product boundaries in PRODUCT.md.
- EnergyCard reused for the native illustration and interactive evidence preview.
  Unique heading IDs use React useId; preview updates retain aria-live.
- All existing current-source feature descriptions, release facts and full privacy
  and support content retained. No analytics, remote models, new dependencies,
  registration flows or external font requests added.
- Licensed local fonts; square 48px buttons, full-label switches, keyboard skip
  link, visible focus on both light and dark grounds, reduced-motion rules.

## Validation

Passed `npm run site:type-check`, `npm run site:build`, and `git diff --check`.
Production output: JS 229.65 kB / 71.67 kB gzip, route CSS 8.28 kB / 2.22 kB gzip,
plus shared brand.css and local font files (22.28 kB + 87.55 kB).

Browser checks against the production preview:

- Homepage at 1440, 1024, 768, 390 and 320 CSS pixels: no horizontal overflow,
  duplicate IDs or broken section anchors; fonts and wave assets loaded.
- Both records missing: unavailable estimate, each record shown as missing.
- Caffeine only: 95 mg, sleep missing, estimate unavailable.
- Sleep only: 7 h 10 m, illustrative 68/100, caffeine missing.
- Both: illustrative 74/100 with source labels; Clear restores missing state.
- Space toggles the focused sleep switch. Control labels/roles and the native
  accessibility tree were inspected. No app console errors/warnings observed.
- Computed homepage text contrast: minimum 5.31:1 in the sampled rendered state.
  Focus outlines also adapt to the dark release section.
- Privacy and support routes load the shared style and retain their return links.
- Exact screenshot viewport dimensions confirmed per tab (capture-metrics.json).

The mechanical design detector returned one warning: Space Grotesk is widely
used. Retained deliberately because it is the primary reference's body face.
The skill launcher initially lacked executable permissions; invoked through sh
for the detector. No model switch, paid fallback or additional worker was used.

### Scoped finish review

Disposition: **ship** (ready for local review; no deployment implied).
Review performed inline to honor the explicit one-worker constraint.

- Persistence: website-specific product/design files and token sidecar recorded.
- Fidelity: condensed typography, exact palette and strong rules match the
  requested family; the native illustration is an intentional product distinction.
- Ceiling: editorial structure retained without copying the portfolio's photo
  cover, project grid, or decorative motion.
- Material fixes: duplicate font fetch removed; dark focus ring improved; hidden
  skip link clipped to prevent full-page capture artifacts. Confirmed in captures.
- Keep: truthful release status and synthetic/missing/estimated distinctions.

Limits: browser emulation, not physical devices; Safari/Firefox and a full
VoiceOver session were not tested. Native Swift/Xcode tests were not run because
all changed files are website-only. No push, merge or deployment performed.

## Screenshots

Before means the live deployed Aurora site. After means this local production
build. Compare each pair at the same verified viewport size:

| View | Before | After |
| --- | --- | --- |
| Desktop, 1440 × 1000 | [Before](review/screenshots/aurora-desktop-before.jpg) | [After](review/screenshots/aurora-desktop-after.jpg) |
| Tablet, 768 × 1024 | [Before](review/screenshots/aurora-tablet-before.jpg) | [After](review/screenshots/aurora-tablet-after.jpg) |
| Mobile, 390 × 844 | [Before](review/screenshots/aurora-mobile-before.jpg) | [After](review/screenshots/aurora-mobile-after.jpg) |

Run locally: `npm ci --prefix website`, `npm run site:build`, then
`npm --prefix website run preview -- --host 127.0.0.1 --port 4175`.
