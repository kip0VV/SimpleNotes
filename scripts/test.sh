#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_root/build"
source_files=()
while IFS= read -r -d '' source_file; do
  source_files+=("$source_file")
done < <(find "$project_root/Sources" -name '*.swift' ! -name main.swift -print0)
xcrun swiftc -swift-version 5 "${source_files[@]}" "$project_root/Tests/main.swift" \
  -framework Cocoa -framework WebKit -framework QuartzCore -framework Carbon \
  -framework UserNotifications -o "$project_root/build/SimpleNotesTests"
"$project_root/build/SimpleNotesTests"
