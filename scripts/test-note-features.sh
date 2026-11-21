#!/bin/bash
# Deliberately compile/run only the new feature components and their checks.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/simplenotes-features.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 \
  "$project_root/Sources/SimpleNotes/NoteMetadata.swift" \
  "$project_root/Sources/SimpleNotes/NoteVersionHistory.swift" \
  "$project_root/Sources/SimpleNotes/NoteHistoryController.swift" \
  "$project_root/Sources/SimpleNotes/NotePDFExporter.swift" \
  "$project_root/Tests/NoteFeatures/main.swift" \
  -framework Cocoa -framework WebKit -framework PDFKit -o "$test_dir/NoteFeatureTests"
"$test_dir/NoteFeatureTests" "$project_root/Resources"
