#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
cp "$repo_dir/tests/native/StoragePrivacyTests.swift" "$test_dir/main.swift"
swiftc "$repo_dir/ios/AURORA/StoragePrivacy.swift" "$test_dir/main.swift" -o "$test_dir/storage-privacy-tests"
"$test_dir/storage-privacy-tests"
