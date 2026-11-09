#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
"$project_root/scripts/build.sh" --universal
output="$project_root/build"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$project_root/Resources/Info.plist")
staging=$(mktemp -d "$output/dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
cp -R "$output/SimpleNotes.app" "$staging/"
ln -s /Applications "$staging/Applications"
printf 'Перетащите SimpleNotes в Applications. При первом запуске выберите папку заметок.\nИнструкция — https://github.com/kip0VV/SimpleNotes#установка\n' > "$staging/Начните здесь.txt"
hdiutil create -volname SimpleNotes -srcfolder "$staging" -format UDZO -ov "$output/SimpleNotes-$version-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$output/SimpleNotes.app" "$output/SimpleNotes-$version-universal.zip"
(cd "$output" && shasum -a 256 "SimpleNotes-$version-universal.dmg" "SimpleNotes-$version-universal.zip" > SHA256SUMS.txt)
