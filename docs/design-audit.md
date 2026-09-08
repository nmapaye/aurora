# Aurora UI Audit — HIG & Liquid Glass Alignment

Audit only — no code changes. Sources: Apple "Adopting Liquid Glass" (TechnologyOverviews),
HIG Materials, HIG Toolbars, HIG Icons (fetched 2026-07-09), and the current `src/` tree.

**Platform reality check:** Aurora is React Native (Expo SDK 54), not SwiftUI/UIKit.
Liquid Glass is a *system* material — the only honest ways to get it are (a) native
components that inherit it (react-native-screens native-stack headers, native sheets,
a native tab bar) and (b) `expo-glass-effect`'s `GlassView` for rare custom cases on
iOS 26+. Everything else is an approximation and, per the adoption guide, custom
re-creations are exactly what Apple says to remove. The plan below therefore leans on
"stop painting custom chrome; let the system draw it."

---

## 1. Screen-by-screen inventory

| Screen | Route | Chrome | Content patterns |
|---|---|---|---|
| **Onboarding** (3 steps) | replaces root until `onboarding.completed` | None (custom in-page header, custom progress segments) | Step 1 sleep target (`StepperField`), Step 2 source pick (`HealthOptionCard`), Step 3 permissions (`SectionCard` + `InlineStatus` + `Button`), sample-data card, Back/Continue row |
| **Summary** (Dashboard) | Tab 1 | Custom 40pt in-page title + custom circular settings button (`AppScreen`) | `HealthAlertCard` (empty/demo state), "Pinned" `HealthMetricCard`s, quick-add buttons, vigilance `StatTile`, recommendations `ListRow`s, recent doses; iPad two-column via `useAdaptiveLayout` |
| **Sleep** | Tab 2 | Same `AppScreen` chrome | Pinned metric cards (hardcoded `#7D7AFF`), Health connection card (`InlineStatus`, inline `ActivityIndicator`, Import/Clear buttons), records list, `SleepSessionItem` |
| **Log** | Tab 3 | Same | Quick Add `HealthOptionCard`s, Custom Entry form (`FormField` + `FieldInput`, text "−"/"+" `Button`s, 6-segment `SegmentedControl`, time button), **hand-rolled RN `Modal` bottom sheet** for the iOS time picker |
| **Insights** | Tab 4 | Same | `SegmentedControl` section switcher, `StatTile` grids, SVG charts (`TimelineGraph`, `CaffeineTodayGraph`), history/export via `HistoryContent` |
| **Vigilance Test** | pushed card (`slide_from_right`) | `AppScreen` + plain "Close" button | Giant custom reaction surface (`Pressable`, 42–48pt numerals), results tiles, Start/Run-again buttons |
| **Settings** | nav `modal` (`slide_from_bottom`) | `AppScreen` + trailing "Done" | Appearance segmented, guidance `StepperField`s, notifications On/Off segmented, About/Privacy/Support `ListRow`s |
| **History** | **orphaned** — `HistoryScreen` exists but is registered in no navigator | — | Wraps `HistoryContent` (also embedded in Insights) |

Navigation shell: native stack with `headerShown: false` everywhere; JS bottom tab bar
with a **custom opaque background view**, custom height (54 + inset), 11pt/500 labels.

Unused legacy kit still in the tree: `Card`, `Chip`, `EmptyState`, `AuroraBackground`,
`DoseQuickButtons`, `MgActiveBadge`, `ScreenContainer` — all styled against the legacy
dark-only `colors` export (rgba-white surfaces), i.e. broken in light mode and dead code.

## 2. Inconsistent visual patterns (with evidence)

**Corner radii — 10 values, no scale.** 10, 12, 14, 16, 18, 22, 24, 28, 32, 999.
Cards alone: `SectionCard` 14, `Card` 16, `HealthOptionCard` 24, `HealthMetricCard`/`HealthAlertCard` 28, `StatTile` 14, time-picker sheet 22.

**Typography — 16 ad-hoc sizes**, no ramp: 11, 12, 13, 14, 15, 16, 17, 18, 22, 24, 28, 30, 33, 40, 42, 48.
Three competing "title" treatments: `AppScreen` title 40/700 (larger than iOS's 34pt large title), `HealthSectionHeader` 28/700, `SectionTitle` 17/600. Body copy is variously 15, 16, and 17. `theme/typography.ts` defines an h1/h2/body/caption ramp that **nothing uses**. Fixed `lineHeight` everywhere will clip under Dynamic Type scaling.

**Spacing** — gaps of 2,3,4,5,6,8,10,12,14,16,18,24; padding mixes 14/16/18/20. No 4/8-pt grid.

**Buttons — six coexisting species.** `Button` (variants `primary/secondary/plain/outline/glass` — "glass" is the *default* and is actually a flat `cardMuted` fill, not glass), plus ad-hoc pressables: `HealthSectionHeader` action (3×4pt padding — far below 44pt target), `HealthAlertCard` action pill, `AppScreen` settings circle, `StepperButton` (32×32 — sub-44pt), `DoseQuickButtons` chips. Two different steppers: icon `StepperButton`s in Settings vs. text "−"/"+" `Button`s in Log.

**Colors.** Semantic palette in `theme/colors.ts` is solid, but screens bypass it: `#7D7AFF` (SleepScreen — the palette already has `colors.sleep #5E5CE6`), `#0A84FF`/`#FF2D55` literals (Dashboard, StepSources), `#FFD60A` + `#1C1C1E` (HealthAlertCard warning header). Legacy `colors` export is a second, contradictory source of truth. Dark mode drops card borders (`borderWidth: scheme === 'dark' ? 0 : 1`) — a per-component trick rather than a system rule.

**Icons.** Ionicons at 8 sizes (16–42); mixed filled/outline without a selected-state rationale (tab bar toggles, but `settings-outline` next to filled `heart`); "Summary" tab uses a heart (reads as Health/favorites, not a summary); weights don't track adjacent text weight (HIG: match icon weight to text).

**Copy case.** Buttons mix Title Case and sentence case: "Load Sample Data", "Custom entry", "Start test", "Clear Samples", "Save intake".

**Toolbars/navigation.** No native header at all → no large-title collapse, no scroll-edge effect, titles scroll away entirely; "toolbar" actions are in-content buttons (settings circle, Close, Done) instead of bar items.

**Sheets/modals.** Settings is a nav modal without grabber/detents; the iOS time picker is a hand-built RN `Modal` (fade animation + custom scrim + custom rounded panel) — no sheet physics, no detents, no keyboard avoidance.

**Empty/loading states.** Four unrelated patterns: `HealthAlertCard` (Dashboard empty), bare `ActivityIndicator` (SleepScreen, BootGate, StepPermissions), disabled-button spinners, and an unused `EmptyState` component. No skeletons, no unified copy tone.

**Accessibility.** `accessibilityRole/Label` exist in the kit but Dashboard has zero; charts are silent to VoiceOver; no Reduce Motion checks (Button/Chip scale-on-press, Reanimated available); fixed line heights + fixed 40–48pt numerals will fight Dynamic Type; several touch targets < 44pt (section-header action, 32pt steppers, ListRow chevron rows at 52pt are fine).

## 3. Custom UI that should be Apple-native

| Current custom | Native replacement |
|---|---|
| `AppScreen` 40pt title + scroll-away header | Native-stack header with `headerLargeTitle` (34pt, collapses to inline, free scroll-edge effect / Liquid Glass on iOS 26 via react-native-screens) |
| Circular in-content settings button | `headerRight` toolbar item (gear icon) |
| VigilanceTest "Close" / Settings "Done" plain buttons | Header bar items (`headerLeft/right`); Close on modals gets system placement |
| JS tab bar with opaque custom background view | System tab bar: remove `tabBarBackground`/custom height first; longer-term a native `UITabBarController` (e.g. react-native-bottom-tabs / Expo Router native tabs) to inherit the floating Liquid Glass bar + scroll-to-minimize |
| Hand-rolled `Modal` time-picker sheet | Native form sheet (`presentation: 'formSheet'` + `sheetAllowedDetents`, grabber) or inline expanding `DateTimePicker` (`display="inline"`) inside the form |
| Custom `SegmentedControl` | Keep (RN has no first-party segmented control) but restyle to system metrics; the **6-segment** Log source picker exceeds segmented-control guidance → native menu (`ContextMenu`/`Menu`) or wrapping chip group |
| Custom steppers (both) | One stepper primitive with 44pt targets; iOS look = value + grouped +/− capsule |
| `InlineStatus` pills, `ListRow`, cards | Keep as custom content (native has no RN equivalent), but tokenize |
| Custom `Alert`-less destructive actions ("Clear Samples") | `Alert.alert` confirmation (native alert), destructive style |

## 4. Where Liquid Glass IS appropriate (navigation/control layer only)

1. **Navigation bars** — enable native headers; on iOS 26 builds they get Liquid Glass + scroll-edge effects automatically. Zero custom code, biggest win.
2. **Tab bar** — the floating glass tab bar is the signature element; today's opaque `palette.card` background view is precisely the "custom background that interferes with Liquid Glass" the adoption guide says to delete.
3. **Sheets** — Settings and the time picker as native sheets pick up the system material, grabber, and detents.
4. **Contextual overlays** — if a floating "+ Log" action is ever added above content, that is the one custom-control candidate for `expo-glass-effect` `GlassView` (regular variant, one element, never stacked).
5. **Vigilance countdown overlay** (if kept as an overlay) — could sit on regular glass since it floats above content briefly.

Rules to honor: regular variant (text legibility) not clear; never glass-on-glass; system components first; test with Reduce Transparency (system components degrade gracefully on their own).

## 5. Where Liquid Glass should NOT be used

- **All cards** (`HealthMetricCard`, `SectionCard`, `StatTile`, alert card) — content layer; HIG says content stays on standard opaque surfaces. Current opaque cards are *correct*; don't "glassify" them.
- **Charts** (`TimelineGraph`, `CaffeineTodayGraph`, `AlertnessRing`) — data legibility; translucency would add noise behind strokes.
- **Forms and inputs** (Log custom entry, note field) — text entry needs stable contrast.
- **The vigilance reaction surface** — a timing-critical, full-attention control; any shimmer/translucency is distraction.
- **Onboarding content and empty states** — reading surfaces.
- **The legacy `Button` "glass" variant and `Chip` "glass" variant** — flat fills masquerading as glass; rename or remove rather than making them translucent (buttons inside scrolling content are content-layer).

## 6. Proposed unified design system

**Tokens module** (`src/theme/tokens.ts` — replace the unused `tokens.json`):

- **Spacing (4-pt grid):** 4, 8, 12, 16, 20, 24, 32. Card padding 16; screen gutter 16 (20 wide layout); inter-card gap 12; section gap 24.
- **Radii (3 + capsule):** `control` 12 (segmented, inputs, small buttons), `card` 16 (standard cards/tiles), `hero` 24 (metric/alert cards), `capsule` 999 (pills, circular buttons). Everything maps to one of these.
- **Type ramp = iOS text styles** (single source, Dynamic Type-ready):
  `largeTitle` 34/700 · `title1` 28/700 · `title3` 20/600 · `headline` 17/600 · `body` 17/400 · `subheadline` 15/400 · `footnote` 13/400 · `caption` 12/400. Numeric heroes: `title1` with tabular numerals; drop the 40/42/48 one-offs. No fixed `lineHeight`; use platform defaults + `maxFontSizeMultiplier` (≈1.6 body, ≈1.3 hero numerals) so Dynamic Type scales without clipping.
- **Color:** keep the semantic `AppPalette`, delete the legacy `colors` export, move every hardcoded hex into palette roles (`sleepAccent`, `warningFill`…). Adopt `PlatformColor` for text/separators on iOS where feasible so Increase Contrast and future system shifts apply for free. Contrast floor 4.5:1 for text, 3:1 for large numerals.
- **Materials/surfaces:** two layers only. *Content* = opaque `card`/`cardMuted` on `groupedBackground` (unchanged). *Chrome* = system-drawn (headers, tab bar, sheets); never painted by the app. No app-drawn blur.
- **Icons:** one family, one sizing rule. Prefer SF Symbols via `expo-symbols` on iOS (Ionicons fallback on Android) — 17pt inline with text, 20pt row accessories, 24pt bare buttons; weight matches adjacent text (regular w/ body, semibold w/ headline); outline as default, filled only for selected states; every icon-only control gets `accessibilityLabel`.
- **Control hierarchy:** one `Button` with `primary` (tint fill) / `tinted` (secondary fill) / `plain` (text); destructive via role, not a variant. One stepper (44pt targets). Segmented control ≤ 4 segments; more options → menu. Minimum 44×44pt for every interactive element.
- **Navigation behavior:** native large-title headers that collapse on scroll; modals as sheets with grabber; tab bar system-styled; Settings reachable from a header toolbar item on every tab (as today, but as a bar item).
- **Accessibility requirements (gate for every PR):** Dynamic Type to XXL without truncating actions; VoiceOver labels on charts (one-sentence data summary) and icon buttons; Reduce Motion disables press-scale/glow (use `AccessibilityInfo.isReduceMotionEnabled` / Reanimated reduced-motion); Reduce Transparency handled by using system chrome; light+dark verified per change.

## 7. Migration plan (safe, incremental steps)

Each step compiles, passes `type-check`/`lint`/`test`, `expo export`, and a light/dark screenshot pass before the next. No user-flow changes anywhere.

1. **Delete dead kit + single color source.** Remove `Card`, `Chip`, `EmptyState`, `AuroraBackground`, `DoseQuickButtons`, `MgActiveBadge`, `ScreenContainer`, orphaned `HistoryScreen` (or register it — decide), and the legacy `colors` export (port `MgActiveBadge`-style stragglers). Pure deletion; zero visual change.
2. **Introduce tokens; mechanical sweep.** Add `tokens.ts` (spacing/radii/type ramp); replace literal radii/font sizes/gaps in `ui.tsx`, `Button`, `AppScreen`, screens with tokens choosing the *nearest current value* — near-zero visual diff, kills the drift.
3. **Consolidate primitives.** One section header, one stepper, `Button` variants renamed (`glass`→`neutral`, fold `outline` in), 44pt touch-target fixes, hardcoded hexes → palette roles, button copy to Title Case.
4. **Native chrome.** Turn on native-stack headers (`headerLargeTitle`, transparent + scroll-edge), move Settings gear/Done/Close into bar items, strip `AppScreen`'s 40pt title (keep it as plain content container), remove custom `tabBarBackground`/height so the system draws the bar. This step alone delivers most of the Liquid Glass adoption on iOS 26 builds.
5. **Native sheets.** Settings → `formSheet` + grabber; replace the hand-rolled time-picker `Modal` with a native sheet or inline picker; add `Alert.alert` confirm on destructive actions.
6. **Icon unification.** `expo-symbols` wrapper (SF Symbols, Ionicons fallback), fix tab metaphors (Summary ≠ heart), apply the sizing/weight rules, selected-state = filled.
7. **Type & Dynamic Type pass.** Apply the ramp via a `AppText` primitive; remove fixed line heights; test at XXL + AX sizes; add `maxFontSizeMultiplier` on hero numerals.
8. **Accessibility & motion pass.** VoiceOver labels for charts and icon buttons; Reduce Motion honored; contrast audit on tertiary text and dark separators.
9. **Optional Liquid Glass accents (iOS 26 only).** Evaluate native bottom tabs (react-native-bottom-tabs) for the true floating glass bar with minimize-on-scroll; `GlassView` only if a floating control is introduced; verify Reduce Transparency/Increase Contrast fallbacks.
10. **QA matrix ship-gate.** Light/dark × Dynamic Type (M, XL, AX1) × Reduce Transparency/Motion/Increase Contrast × iPhone/iPad two-column × iOS 18-and-26 appearance.

Steps 1–3 are pure refactors (safe any time); 4–5 change chrome only; 6–8 are visual polish; 9 is additive and OS-gated.
