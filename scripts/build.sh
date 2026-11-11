#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
output="$project_root/build"
architecture="${1:---universal}"
case "$architecture" in
  --universal) architectures=(arm64 x86_64) ;;
  --native) architectures=("$(uname -m)") ;;
  *) printf 'Usage: %s [--universal|--native]\n' "$0"; exit 1 ;;
esac
mkdir -p "$output"
source_files=()
while IFS= read -r -d '' source_file; do source_files+=("$source_file"); done < <(find "$project_root/Sources" -name '*.swift' -print0)
for cpu in "${architectures[@]}"; do
  printf 'Building %s…\n' "$cpu"
  xcrun swiftc -O -swift-version 5 -target "$cpu-apple-macos13.0" "${source_files[@]}" -framework Cocoa -framework WebKit -framework QuartzCore -framework Carbon -framework UserNotifications -o "$output/SimpleNotes-$cpu"
done
app="$output/SimpleNotes.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [ "${#architectures[@]}" -eq 2 ]; then
  xcrun lipo -create "$output/SimpleNotes-arm64" "$output/SimpleNotes-x86_64" -output "$app/Contents/MacOS/SimpleNotes"
else
  cp "$output/SimpleNotes-${architectures[0]}" "$app/Contents/MacOS/SimpleNotes"
fi
cp "$project_root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_root/Resources/markdown-it.min.js" "$app/Contents/Resources/"
cp "$project_root/Resources/katex.js" "$project_root/Resources/katex.css" "$project_root/Resources/markdown-math.js" "$app/Contents/Resources/"
cp "$project_root/ThirdPartyLicenses/katex.txt" "$app/Contents/Resources/katex-LICENSE.txt"
cp "$project_root/Resources/AppIcon.icns" "$app/Contents/Resources/"
cp "$project_root/ThirdPartyLicenses/markdown-it.txt" "$app/Contents/Resources/markdown-it-LICENSE.txt"
codesign --force --deep --sign - "$app"
printf 'Built %s\n' "$app"
