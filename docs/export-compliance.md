# Encryption export compliance

Answer for v0.1.0 and later builds while the code stays as described:
**`ITSAppUsesNonExemptEncryption = NO`**, i.e. the app uses only exempt
encryption.

The setting is `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in the
Aurora target's Debug and Release build settings (`Aurora.xcodeproj/project.pbxproj`).
It is applied to whichever Info.plist the build uses, so it covers
`Aurora/Info.plist` and the simulator-only `Aurora/Info-Simulator.plist` from
PR #48 without editing either file. Do not also add the key to an Info.plist:
the two plists must stay identical apart from the ATS exception.

## What the code does

- HTTPS through `URLSession` (OS-provided TLS), only to Google
  (`accounts.google.com`, `oauth2.googleapis.com`, `www.googleapis.com`) in
  `Aurora/Services/GoogleCalendarProvider.swift`. Not reachable in v0.1.0
  because Google sign-in isn't configured.
- Plain HTTP to `127.0.0.1:11434` (Ollama on the developer's Mac) only inside
  `#if targetEnvironment(simulator)` in `Aurora/Services/LocalIntelligence.swift`.
  No encryption, and not in device builds.
- Keychain (`SecItem*`) for the Google token, and iOS data protection for
  local files. Both are OS-provided.
- CryptoKit `SHA256` for the OAuth PKCE challenge and `SecRandomCopyBytes` for
  the verifier. These are hashing and random numbers for authentication, not
  data encryption.
- No CommonCrypto, OpenSSL, libsodium, custom ciphers or third-party packages.

Apple, "Complying with encryption export regulations": "Typically, the use
of encryption that's built into the operating system—for example, when your
app makes HTTPS connections using URLSession—is exempt…". Set the key to NO
"if your app—including any third-party libraries it links against—doesn't use
encryption, or if it only uses forms of encryption that are exempt".

## Keeping it true

`scripts/verify-privacy-manifest.py` fails CI if a build configuration loses
the setting, sets it to YES, or code starts using a cipher or crypto library
(CommonCrypto, CryptoKit `AES.GCM`/`ChaChaPoly`/`HPKE`, `SecKeyCreateEncryptedData`,
OpenSSL, libsodium). Run it on the archive to check the built Info.plist:

    python3 scripts/verify-privacy-manifest.py --app build/Aurora.xcarchive

Re-review before adding end-to-end encryption, a VPN or proprietary protocol,
or any third-party SDK.
