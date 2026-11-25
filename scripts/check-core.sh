#!/bin/bash
# Run the repository's unchanged XCTest sources using only Command Line Tools.
# No package downloads, Xcode.app, or writes inside the project are required.
set -euo pipefail

CHECK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_BASE="${RODNYE_CHECK_TMPDIR:-${TMPDIR:-/tmp}}"
CHECK_CACHE="${RODNYE_CHECK_MODULE_CACHE:-${CHECK_BASE%/}/rodnye-core-module-cache}"
CHECK_WORK="$(mktemp -d "${CHECK_BASE%/}/rodnye-core-check.XXXXXX")"
trap 'rm -rf "$CHECK_WORK"' EXIT
mkdir -p "$CHECK_CACHE"

command -v swiftc >/dev/null || { echo 'Swift compiler not found. Install Apple Command Line Tools.' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'Python 3 from Command Line Tools is required for test discovery.' >&2; exit 2; }

python3 "$CHECK_ROOT/scripts/generate-check-runner.py" "$CHECK_ROOT/Tests/FamilyTreeCoreTests" "$CHECK_WORK/Runner.swift"

COMMON_FLAGS=(-swift-version 5 -module-cache-path "$CHECK_CACHE" -I "$CHECK_ROOT/Sources/CSQLite")
CORE_SOURCES=("$CHECK_ROOT"/Sources/FamilyTreeCore/*.swift)
TEST_SOURCES=("$CHECK_ROOT"/Tests/FamilyTreeCoreTests/*.swift)

swiftc "${COMMON_FLAGS[@]}" -parse-as-library -enable-testing \
    -emit-module -emit-library -static -module-name FamilyTreeCore \
    -emit-module-path "$CHECK_WORK/FamilyTreeCore.swiftmodule" \
    "${CORE_SOURCES[@]}" -o "$CHECK_WORK/libFamilyTreeCore.a"

# A narrow assertion-compatible module, never linked into the app or SwiftPM tests.
swiftc "${COMMON_FLAGS[@]}" -parse-as-library \
    -emit-module -emit-library -static -module-name XCTest \
    -emit-module-path "$CHECK_WORK/XCTest.swiftmodule" \
    "$CHECK_ROOT/scripts/XCTestCLI.swift" -o "$CHECK_WORK/libXCTest.a"

swiftc "${COMMON_FLAGS[@]}" -I "$CHECK_WORK" -L "$CHECK_WORK" \
    "${TEST_SOURCES[@]}" "$CHECK_WORK/Runner.swift" \
    -lFamilyTreeCore -lXCTest -lsqlite3 -o "$CHECK_WORK/check-core"

# Verify every supported assertion's failure path, thrown tests, lifecycle errors,
# and the nonzero exit contract before trusting any production test result.
set +e
"$CHECK_WORK/check-core" --verify-harness > "$CHECK_WORK/harness.log" 2>&1
HARNESS_STATUS=$?
set -e
if [ "$HARNESS_STATUS" -ne 1 ] || ! grep -q '^Harness self-check verified$' "$CHECK_WORK/harness.log"; then
    cat "$CHECK_WORK/harness.log" >&2
    echo 'Assertion harness self-check failed.' >&2
    exit 2
fi
printf '%s\n' 'Assertion harness self-check passed (including expected failures and exit status).'
"$CHECK_WORK/check-core"
