# Security Policy

## Reporting a vulnerability

The intended channel is GitHub's
[private vulnerability reporting](https://github.com/nmapaye/aurora/security/advisories/new).
It was enabled with owner approval and verified through GitHub on October 25,
2026. Use the private form above rather than a public issue. TestFlight feedback
or another owner contact may also be used if a verified private route was supplied.
Do not post security findings, Health records, calendar details, conversation
contents or credentials in public issues. No separate fallback private contact is certified by this checkout.

Once the channel is available, include the finding, reproduction steps and app
version or commit. The owner should confirm the response expectation before
inviting testers. Release preflight checks that the documented GitHub private
reporting channel is enabled; it does not enable it automatically.

## Scope

Aurora keeps all records on the device. If the person turns each one on, it
reads sleep and caffeine from Apple Health and adds caffeine they saved in
Aurora, changing or deleting only samples Aurora wrote. Reports about local data exposure, backup handling, the
HealthKit integration, exported CSV files, and the repository's CI and release
workflows are all in scope.

## Supported versions

Only the latest build on `main` receives fixes.
