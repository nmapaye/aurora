# Aurora SwiftUI spike

This is a small interaction prototype following the September 8 cancellation of the full rewrite. It lives on `nmapaye-bot/aurora-native-spike`, based on main at `cc79bf1`. The canceled integration remains preserved separately. No main merge is part of this spike.

## What it tests

- Can Today lead with bedtime caffeine while keeping common logging to one tap after recipe setup?
- Does dragging consumed volume feel understandable, and do container size and espresso shot count behave independently?
- Do native time controls and an explicit accepted sleep plan make variable bedtimes easy to adjust?
- Can the same SwiftUI screen implementation adapt to a compact iPhone and a sidebar layout on iPad?

The spike uses SwiftUI, Charts and Observation with a Foundation-only domain module. The Mac preview shares the screen implementation. iOS uses native time wheels; macOS uses its native date/time field. The Mac preview provides an immediate way to try the controls while full Xcode remains paused.

## Try it

From the repository root, run `bash scripts/build-native-spike.sh`. Open the resulting `spikes/AuroraNative/output/Aurora Spike.app`. The command builds only the Swift package and does not install Node dependencies or touch Aurora's application data.

For iPhone/iPad simulator or device use, open `ios/AURORA.xcworkspace` and select the **AuroraSpike** scheme. The separate application uses `com.nmapaye.aurora.spike`; production Aurora retains its bundle identifier and targets. Device installation needs full Xcode and a signing team. The spike has no CocoaPods dependencies.

Try the two favorites, choose a usual shot count, then repeat a drink and Undo it. Open a favorite's serving menu, change container, drag to half, and compare the displayed volume and caffeine. Use Browse for matcha and brewed-coffee examples. Edit the next sleep time, cancel once, then accept a different time and watch the bedtime projection change. Resize the Mac window and try VoiceOver.

## Boundaries

All records are clearly labeled preview/example data, and edits are session-only. Closing and reopening resets the prototype. There is no HealthKit connection, migration, production storage, notification scheduling, widget, Siri, signing, TestFlight or release implementation. A simulator artifact cannot be installed on a physical iPhone/iPad.

The espresso favorites require an initial recipe choice. Example estimates are not a claim about the user's actual drinks. My Tumbler is 16 US fl oz, stored as 473.176473 ml. Fixed-ingredient caffeine stays constant when the vessel changes; consumed fractions scale the prepared drink. Concentration-based recipes scale by consumed volume. Existing Aurora presets and historical data are untouched.

The prototype's results will guide a later implementation decision. It does not establish full feature parity, migration safety, real Health behavior, App Store readiness or physical-device accessibility.

## Verification

Run `bash scripts/test-native-spike.sh` for domain tests. `Native SwiftUI Spike` CI is configured to build the shared code and unsigned iOS Debug/Release applications on stable Xcode 26.6. It also runs the favorite, half-serving, Undo and accepted-sleep flows on iPhone 13 and iPad Air simulators, with screenshots attached. The manually maintained workspace includes a separate spike project; it does not change the production target or run Expo prebuild.

Verified locally on September 8, 2026:

- All 18 domain tests pass, covering recipe/container independence, partial servings, immutable history, Undo conflicts/expiry, volume conversion, midnight and DST sleep suggestions, explicit acceptance, and example exclusion.
- The shared SwiftUI screens compile with Swift 6.3.2 for macOS 14+. The packaged Mac application launches and exposes Today and drink adjustment controls through the native accessibility tree.
- Independent specification/code review found and resolved two issues: navigation now stays on the same page when switching window layouts, and tumbler coffee can switch both ways between espresso and brewed preparation. Favorite and sleep actions have at least 44-point touch targets.
- Project and privacy plist validation, shell syntax, and whitespace checks pass.

iOS builds, simulator screenshots, physical-device behavior and a full VoiceOver/Dynamic Type pass remain unverified. Full local Xcode is still paused. Publishing the isolated branch for remote CI requires the user's approval; the local prototype can be used immediately.
