#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_root/build"
rm -f "$project_root/build/test-result.txt"
test_app="$project_root/build/SimpleNotesTests.app"
mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources"
/usr/libexec/PlistBuddy -c Clear "$test_app/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add CFBundleIdentifier string io.github.kip0vv.SimpleNotes.tests" "$test_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add CFBundleExecutable string SimpleNotesTests" "$test_app/Contents/Info.plist"
cp "$project_root/Resources/markdown-it.min.js" "$project_root/Resources/katex.js" "$project_root/Resources/katex.css" "$project_root/Resources/markdown-math.js" "$test_app/Contents/Resources/"
source_files=()
while IFS= read -r -d '' source_file; do
  source_files+=("$source_file")
done < <(find "$project_root/Sources" -name '*.swift' ! -name main.swift -print0)
xcrun swiftc -swift-version 5 "${source_files[@]}" "$project_root"/Tests/*.swift \
  -framework Cocoa -framework WebKit -framework QuartzCore -framework Carbon \
  -framework UserNotifications -o "$project_root/build/SimpleNotesTests.app/Contents/MacOS/SimpleNotesTests"
"$test_app/Contents/MacOS/SimpleNotesTests"
