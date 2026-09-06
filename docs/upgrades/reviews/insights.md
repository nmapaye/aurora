# Insights batch review

Scope: features 31–40. Implementation and independent domain/UI fix-reviews passed. Physical device acceptance remains pending.

## Domain evidence

Independent tests cover the three-prior-test vigilance baseline, the inclusive 30-minute pairing boundary and deterministic ties, five-pair summary requirements, confirmed zero versus missing weekday records, overlapping sleep duration, bedtime observation eligibility, calendar changes across DST, weekly user targets, future-input exclusion, and input immutability.

Model inspection preserves residual caffeine from older doses while identifying missing intake coverage for the inspected date. The model formula is unchanged. Nearest completed vigilance tests remain visible when their reaction median is unavailable; only pairs with valid reaction medians contribute to the five-pair summary gate.

## UI review

A wide-layout review found that chart tap coordinates were measured across the container while the SVG retained a centered aspect ratio. The resulting mismatch could select an interior time when tapping near a plotted endpoint on iPad. The SVG now stretches explicitly and tap mapping accounts for the plot inset. Independent endpoint tests pass at widths 320 and 900.

Native builds and physical iPhone/iPad layout, VoiceOver, large text and Reduce Motion verification remain pending.


Contextual explanation review corrected two mismatches. Summary explains its latest single stored sleep interval, while Sleep/Explorer describe grouped daily totals. Planning explicitly explains its personal recorded baseline plus hypothetical scenario inputs. Existing Insights bedtime guidance now uses the full personal dose history consistently across range changes and the shared schedule. Regression coverage excludes sample and future doses.

Final Node 24 type-check and lint passed. Full Jest passed 78 suites and 400 tests, with one timezone-specific skip covered by the separate New York gate (35 tests passed). Root iOS Expo export passed with 1659 modules after the explanation changes. Diff whitespace and verification-script syntax checks passed. Evidence is retained in ../evidence/insights-jest.txt. Website code is unchanged from the prior passed checks.
