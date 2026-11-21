#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/simplenotes-reading.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 \
  "$project_root/Sources/SimpleNotes/ReadingFocusController.swift" \
  "$project_root/Tests/ReadingFocus/main.swift" \
  -framework Cocoa -o "$test_dir/ReadingFocusTests"
"$test_dir/ReadingFocusTests"
