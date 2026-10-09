# Claude: Aurora premium release design

## Assignment

Preserve existing cards and trust boundaries. Improve native design and interactions
using `design.md`, the shared Swift theme, and the synthetic Debug Design Gallery.
Read `agents.md`, `PRODUCT.md`, `CLAUDE.md`, and the installed iOS guidance first.

Start with caffeine logging → editable review → saved receipt → Undo. Make the
hierarchy, field alignment, units, source labels, action states and transition feel
coherent in light/dark and large text. Do not invent record values or change Save,
Undo, validation, snapshot or approval behavior. Keep animation interruptible and
optional under Reduce Motion. Preserve the gentle Aurora processing rim and palette.

Then refine other existing response experiences and secondary screens against the
same tokens. Use purposeful expansion/selection/receipt motion, not the same entrance
on every card or distracting motion around readable evidence. Keep iPad max-width
layout and system sheets/date pickers. Update the guide when introducing a token.

## Ownership and execution

Use only the assigned isolated worktree on `claude/aurora-premium-release`.
Allowed edits: `Aurora/Theme`, `Aurora/Screens/Assistant/AssistantCardView.swift`,
`DesignGalleryView.swift`, visual components, and this handoff's design evidence.
Do not edit AppModel, AssistantModel, services, AuroraCore, erasure SettingsView,
tests, CI, signing, metadata, original checkouts, or agent/tool configuration.
Coordinate any interface changes with Codex. No cloud, keys, account permissions,
pushes, calendar writes, or real record deletion. Do not run simulator tests while
Codex holds the test lane. Codex will build and capture the combined result.

Deliver coherent small commits or reviewed file changes, explain what changed and
why, list unverified items, and provide a final handoff. If no screenshot tool is
available, state that honestly and request Codex's capture pass; never claim visual
QA from code review alone. Current baseline screenshots in the conversation are
references, not proof of your final implementation.
