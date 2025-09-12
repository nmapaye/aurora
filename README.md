# AURORA

Caffeine + sleep tracker with a computed alertness score

## Native Sync (Prebuild) — Option A

This repo commits `ios/` and `android/` folders. When native folders exist, Expo/EAS will not automatically sync native config from `app.json` on build. After changing any native-related fields in `app.json` (e.g., `icon`, `splash`, `ios`, `android`, `plugins`), re-generate native projects locally and commit the changes.

Scripts:

- `npm run sync:native` — runs `expo prebuild --no-install` to apply config changes without reinstalling node modules.
- `npm run sync:native:clean` — runs `expo prebuild --clean` to fully regenerate native projects (use when changing icons/splash or after major SDK upgrades).

Typical flow:

1. Edit `app.json` (icons, splash, plugins, etc.).
2. Run `npm run sync:native`.
3. Review and commit changes under `ios/` and `android/`.
4. Build locally or with EAS.

Note: If you prefer Config‑Driven builds (no native folders), delete `ios/` and `android/` and let EAS prebuild on the server each build instead.
