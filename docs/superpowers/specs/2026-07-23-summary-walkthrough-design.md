# Summary Walkthrough Design

Date: 2026-07-23  
Status: Approved for implementation planning

## Summary

Aurora will add a one-time walkthrough that begins after a new user completes
the existing three-step setup. The walkthrough operates directly on the real
Summary screen and progressively reveals its content with a restrained
lift–fade–settle animation.

The experience is hybrid: content animates automatically, then pauses at four
short teaching moments with **Skip** and **Next** or **Finish** actions. It uses
the user's real state, never inserts sample data, and cannot be replayed after
completion.

## Goals

- Explain how to read and use Summary immediately after setup.
- Make the first transition into the app feel polished and intentional.
- Animate real Summary content without maintaining a duplicate screen.
- Work with empty, Health-connected, and user-selected demo states.
- Adapt to iPhone, iPad, light and dark appearance, Dynamic Type, VoiceOver,
  and Reduce Motion.
- Persist completion so the walkthrough runs once for a genuinely new user.

## Non-goals

- Replacing or redesigning the existing three-step setup.
- Adding a replay command in Settings.
- Adding contextual hints after app updates.
- Loading sample data on the user's behalf.
- Building a reusable cross-app spotlight-tour framework.
- Changing navigation, Health permissions, caffeine calculations, or alertness
  calculations.
- Animating every individual word, icon, or chart mark.

## Chosen Direction

The approved direction is an integrated staged reveal:

- Existing Summary sections remain the source of truth.
- Meaningful UI blocks receive lightweight reveal wrappers.
- The screen scrolls between semantic teaching targets rather than measuring
  absolute screen-coordinate spotlight cutouts.
- A fixed coach card sits above the tab bar.
- Motion follows the approved **Option A: Soft spring cascade** direction.

This avoids the layout fragility of a spotlight overlay and the duplicated UI
of a separate walkthrough replica.

## User Flow

### Entry

1. The user completes the existing setup.
2. Aurora mounts its normal tab navigator on Summary.
3. Summary completes its first layout pass and waits approximately 300 ms for
   the navigation transition to settle.
4. The walkthrough begins if onboarding is complete and
   `summaryWalkthroughCompleted` is false.

The tab bar remains visible, but its non-Summary destinations are disabled
until Skip or Finish. Summary content cannot be manually scrolled or activated
during the walkthrough, preventing accidental navigation while the screen
moves between teaching moments.

### Stage 1: Orientation

Reveal order:

1. Summary title and header.
2. The current-state alert card, when present.

Coach copy:

- Progress: `1 of 4`
- Title: `Your day at a glance`
- Body: `Aurora brings caffeine, sleep, and alertness together.`
- Actions: `Skip`, `Next`

An absent alert card does not leave an animation gap or delay.

### Stage 2: Key Signals

After the first coach card exits, Summary scrolls to Pinned. The Pinned heading
and its metric cards reveal with an approximately 80 ms stagger.

Coach copy:

- Progress: `2 of 4`
- Title: `See what shapes alertness`
- Body: `These signals show how caffeine, sleep, and vigilance shape your day. Tap any card later to explore it.`
- Actions: `Skip`, `Next`

On a wide iPad layout, Pinned cards reveal down the left column while the Today
panel settles into the right column. If the targets are already fully visible,
the screen does not perform unnecessary scrolling.

### Stage 3: Fast Logging

Summary scrolls to Log. Quick-add controls and Custom Entry reveal as a compact
cascade, followed by Recent Activity.

Coach copy:

- Progress: `3 of 4`
- Title: `Log in a tap`
- Body: `Use a common amount, or open Custom Entry when you need more detail.`
- Actions: `Skip`, `Next`

The walkthrough does not submit a dose or modify existing activity.

### Stage 4: Explore

The final coach card explains the persistent bottom navigation without adding a
spotlight or moving the tab bar.

Coach copy:

- Progress: `4 of 4`
- Title: `Keep exploring`
- Body: `Sleep manages rest data, Log records caffeine, and Insights reveals patterns over time.`
- Actions: `Skip`, `Finish`

Finish dismisses the coach card, restores scrolling and interaction, and leaves
the user at the walkthrough's final scroll position.

### Skip and interruption

- Skip is available on every coach card.
- Skip immediately reveals all remaining content, restores interaction, and
  persists completion.
- Finish reveals any remaining content, restores interaction, and persists
  completion.
- If the app closes or crashes before Skip or Finish completes, the persisted
  flag remains false and the walkthrough restarts from stage 1 on the next
  launch.
- No partial walkthrough stage is persisted.

## Visual and Motion Design

### Reveal motion

Each meaningful block begins at approximately:

- Opacity: `0`
- Vertical offset: `14 pt`
- Scale: `0.97`

It settles at full opacity, zero offset, and scale `1` using a highly damped
spring with almost no bounce. Items within a group begin roughly 80 ms apart.
Each stage's complete reveal stays under one second.

The coach card uses the same motion language with a shorter transition. It
appears only after the target scroll and reveal have settled. A best-effort
selection haptic marks each teaching moment.

### Coach card

The coach card is a fixed overlay above the tab bar, not part of the scrollable
content. It uses:

- Aurora's opaque card surface
- Existing semantic text and tint colors
- Existing hero corner radius
- A subtle border
- A soft shadow in light appearance
- A maximum readable width on iPad
- A small progress label, concise title and body, plain Skip, and primary
  Next or Finish

There is no scrim, blur, glass effect, or spotlight cutout. The underlying
content remains visually legible and retains its normal hierarchy.

### Interaction timing

- Next is disabled while a scroll or reveal transition is active.
- The coach card does not appear until its target content has settled.
- Underlying controls and manual scrolling remain disabled until Skip or
  Finish.
- Repeated Next presses cannot advance more than one stage.

## Architecture

### Persisted state

Extend the existing `Onboarding` state with:

```ts
summaryWalkthroughCompleted: boolean;
```

Add a focused store action:

```ts
completeSummaryWalkthrough: () => void;
```

`completeSummaryWalkthrough` sets the flag to true. Skip and Finish use this
same action.

The field must be included in:

- `defaultOnboarding`
- `normalizePersistedState`
- The non-default persistence fixture
- Store migration coverage

Increment the persisted store version from 3 to 4.

Migration behavior is explicit:

- A stored version 3 user with `onboarding.completed === true` migrates with
  `summaryWalkthroughCompleted === true`, preventing an update from launching
  an unexpected tour.
- A stored version 3 user with incomplete onboarding migrates with
  `summaryWalkthroughCompleted === false` and receives the walkthrough after
  completing setup.
- A new installation starts with both onboarding and walkthrough incomplete.

`completeOnboarding` and `loadDemoData` continue to complete setup but do not
complete the walkthrough. If the user explicitly chooses sample data during
setup, that dataset is their real Summary state for the subsequent walkthrough.

### Pure step definition

Create a small pure module containing:

- The ordered stage IDs
- Progress labels
- Coach copy
- The semantic reveal groups for each stage
- Pure transition helpers for Next, Skip, and Finish

This module has no React Native or animation dependency. It is the testable
source of truth for walkthrough order and copy.

### `useSummaryWalkthrough`

A dedicated hook owns:

- Whether the walkthrough should start
- The active stage
- Transition locking
- Section layout positions
- Programmatic scrolling
- Reveal-group activation
- Coach-card visibility
- Reduce Motion behavior
- Accessibility announcements and focus
- Best-effort haptics
- Skip and Finish completion

The hook starts only after the screen has completed a usable layout. It keeps
stage state in memory and relies on the store only for final completion.

### `WalkthroughReveal`

This presentational component accepts:

- Whether the walkthrough is active
- Whether its content has been revealed
- A stagger index
- Reduce Motion state
- Normal children

The component remains in layout while visually hidden, allowing section
positions to be measured before reveal. When the walkthrough is inactive or
complete, it renders content immediately and does not replay entry motion.
While a reveal group is visually hidden, it is also hidden from the
accessibility tree.

### `SummaryWalkthroughCoach`

This component accepts the current pure step definition and callbacks for Skip
and Next or Finish. It owns presentation and accessibility semantics only. It
does not change store state or manage stage timing.

### `AppScreen`

Add narrowly scoped optional support for:

- A scroll ref supplied by the caller
- Programmatic scroll coordination
- Temporarily disabling manual scrolling
- A fixed bottom overlay
- Extra bottom content inset while an overlay is present
- Opting the Summary header into the reveal sequence

Existing callers receive the current behavior without modification.

### `RootTabs`

RootTabs derives whether a new-user Summary walkthrough is pending from the
persisted onboarding state. While it is pending, Sleep, Log, and Insights remain
visible but expose a disabled accessibility state and do not respond to taps.
Skip or Finish updates the persisted flag and immediately restores normal tab
navigation. No route names or navigation destinations change.

### `DashboardScreen`

Dashboard composes the controller, reveal wrappers, semantic layout anchors,
and coach card around its existing real sections. Summary calculations,
navigation targets, button callbacks, and child component APIs remain
unchanged.

## Scrolling and Adaptive Layout

Section targets record their content-relative vertical positions through
`onLayout`. The controller scrolls to a clamped target position with enough top
clearance to preserve context.

- iPhone uses animated scrolling unless Reduce Motion is enabled.
- iPad skips scrolling when the relevant content is already visible.
- Rotation or width-class changes invalidate recorded positions, remeasure the
  targets, and preserve the active semantic stage.
- A failed or missing measurement never blocks progress. Aurora reveals the
  target group immediately and continues without scrolling.
- The content container includes enough bottom space that the coach card never
  obscures the final teaching target.

## Accessibility

- All coach actions meet the 44-by-44-point minimum touch target.
- The coach title is exposed as a heading.
- Each newly visible coach step is announced through VoiceOver after its target
  content settles.
- Accessibility focus moves to the coach heading without exposing visually
  hidden reveal groups.
- Temporarily unavailable tab destinations expose a disabled accessibility
  state.
- Dynamic Type increases coach-card height rather than truncating copy.
- The coach card uses the existing semantic palette in light and dark modes.
- Reduce Motion removes translation, scale, spring, stagger, animated
  scrolling, and haptics. Content uses either an immediate reveal or a short
  opacity transition.
- If reading Reduce Motion state fails, Aurora uses the conservative fade-only
  behavior.

## Failure Handling

- Haptic errors are ignored.
- Accessibility announcement or focus errors do not block stage progression.
- Missing layout anchors fall back to immediate reveal without scrolling.
- A transition lock prevents duplicate presses and overlapping animations.
- Cleanup cancels pending timers, animation callbacks, and accessibility work
  when Dashboard unmounts.
- Completion is persisted before the coach card is permanently dismissed. If
  persistence later rehydrates, the normalized flag remains authoritative.
- The walkthrough never prevents access to Skip because of a missing target or
  failed animation.

## Testing Strategy

### Unit tests

- Step order and copy are complete and stable.
- Next advances exactly one stage.
- Next does nothing while transition-locked.
- Skip and Finish produce the completed state.
- The last stage cannot advance past completion.
- Missing target measurements select the no-scroll fallback.
- Reduce Motion selects non-spring, non-staggered behavior.

### Store tests

- New installations default to walkthrough incomplete.
- `completeSummaryWalkthrough` sets the flag.
- Version 3 completed-onboarding state migrates to walkthrough complete.
- Version 3 incomplete-onboarding state migrates to walkthrough incomplete.
- The persistence fixture round-trips a non-default walkthrough flag.
- `completeOnboarding` and `loadDemoData` do not prematurely complete the
  walkthrough.

### Component and flow tests

- Summary renders normally when the walkthrough is already complete.
- New setup completion starts stage 1 after layout.
- Optional alert-card absence does not stall stage 1.
- Non-Summary tabs are disabled while the walkthrough is pending and re-enable
  after Skip or Finish.
- Skip reveals content and restores interaction from every stage.
- Finish restores interaction and retains the final scroll position.
- Coach actions and headings have correct accessibility labels and roles.

### Manual verification

- Empty manual setup
- Health-connected setup with sleep data
- User-selected sample data
- Light and dark appearance
- iPhone and iPad layouts
- Portrait and landscape transitions
- Dynamic Type at default, XL, and accessibility sizes
- VoiceOver
- Reduce Motion
- Backgrounding and reopening during the walkthrough

### Repository gates

- `npm run type-check`
- `npm run lint`
- `npm test -- --runInBand`
- `npx expo export --platform ios`
- `npm run site:type-check`
- `npm run site:build`

Native simulator build gates remain part of release validation but are not
required to prove the JavaScript-only walkthrough implementation when a stable
Xcode 26.6 environment is unavailable.

## Acceptance Criteria

- A genuinely new user sees the walkthrough once immediately after setup.
- An existing completed-onboarding user does not see it after upgrading.
- Summary uses the user's actual data and the walkthrough creates no records.
- Four approved teaching moments appear in order.
- The selected soft spring cascade is polished, restrained, and completes each
  stage in under one second.
- Skip works from every stage and permanently prevents replay.
- Finish permanently prevents replay.
- Underlying controls cannot be activated during the walkthrough.
- Non-Summary tab destinations remain visible but cannot be activated until
  Skip or Finish.
- Summary behaves exactly as before once the walkthrough is complete.
- Reduce Motion, VoiceOver, Dynamic Type, iPhone, and iPad behaviors match this
  specification.
- Persistence normalization and fixtures include the new field.
