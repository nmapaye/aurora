# Security Policy

## Reporting a vulnerability

Report security problems privately through GitHub's
[private vulnerability reporting](https://github.com/nmapaye/aurora/security/advisories/new).
Please don't open a public issue for them.

Include what you found, the steps to reproduce it, and the app version or
commit you tested. You should get a reply within a week.

## Scope

Aurora keeps all records on the device. If the person turns each one on, it
reads sleep and caffeine from Apple Health and adds caffeine they saved in
Aurora, changing or deleting only samples Aurora wrote. Reports about local data exposure, backup handling, the
HealthKit integration, exported CSV files, and the repository's CI and release
workflows are all in scope.

## Supported versions

Only the latest build on `main` receives fixes.
