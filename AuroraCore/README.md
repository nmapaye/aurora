# AuroraCore

Aurora's logic as a Swift package with no dependencies beyond Foundation:
models, the alertness estimate, Summary, Sleep, Insights and Log
presentation, Sample Data, CSV export, onboarding and walkthrough rules,
deep links, and the reader for the React Native build's stored data.

## Running the tests

On macOS with Xcode 26 or newer, or anywhere with a Swift 6 toolchain:

```sh
cd AuroraCore
swift test
```

On Linux, the same image CI uses works:

```sh
docker run --rm -v "$PWD":/src -w /src/AuroraCore swift:6.2 swift test
```

CI (`.github/workflows/core-ci.yml`) runs both, and reports failing tests
as annotations on the check.

## Fixtures

`Tests/AuroraCoreTests/Fixtures` holds two kinds of expected data. Neither
is regenerated to make a failing test pass. A difference means the Swift
port drifted.

**`core-UTC.json`, `core-America_Los_Angeles.json`, `legacy.json`** are
outputs of the TypeScript originals, written by
`tests/fixtures/exportCoreFixtures.spec.ts` in the React Native build,
once per time zone:

```sh
AURORA_FIXTURE_OUT=AuroraCore/Tests/AuroraCoreTests/Fixtures TZ=UTC npx jest tests/fixtures
AURORA_FIXTURE_OUT=AuroraCore/Tests/AuroraCoreTests/Fixtures TZ=America/Los_Angeles npx jest tests/fixtures
```

The React Native build, that spec and the TypeScript it calls have been
removed. To regenerate these fixtures, check out commit `0013c38`, the
last one with `tests/fixtures/exportCoreFixtures.spec.ts`, then run
`npm ci` and the commands above.

**`mmkv/`** holds files written by MMKV Core v2.0.0, the version that
react-native-mmkv 3.3.0 shipped in the React Native build. They were not
written by `MMKVReader.encode`. `Tools/mmkv-fixtures/generate.py` fetches
that package from npm and checks it against the integrity hash in the old
`package-lock.json`. It then builds the vendored core with CMake and
writes each scenario through the calls the React Native host object made.
`manifest.json` records the package, its integrity hash, the core version,
each file's SHA-256, and the values MMKV itself read back. To regenerate
(needs python3, npm, cmake, a C++20 compiler and zlib):

```sh
python3 AuroraCore/Tools/mmkv-fixtures/generate.py
```

The generator ran on Linux. MMKV uses the same file layout on every
platform, but these files were not produced on an iPhone.
