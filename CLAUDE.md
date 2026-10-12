# Aurora collaboration

Read `agents.md`, `PRODUCT.md`, `design.md`, and the current handoff before editing.
Use `.claude/skills/impeccable/reference/ios.md` for native platform conventions.
Native accessibility, Aurora's user-approved palette, and product trust rules
override web-only skill recommendations. Skills are advisory; no automatic hooks
are installed and no new cloud/API-key configuration is allowed.

Claude owns UI/theme work in its isolated release-design worktree. Codex owns
AuroraCore, services/storage, settings deletion, tests, CI and integration. Agree
before touching shared files. No pushes or publications. Do not modify original
Aurora checkouts. Use small local commits and include actual verification evidence.

Only one simulator UI-test job at a time on this Mac. Codex schedules the test lane.
Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` per command; do not
change global xcode-select or signing/team settings.
