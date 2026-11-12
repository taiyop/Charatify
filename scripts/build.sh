#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
app_path="$PWD/build/Charatify.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp .build/release/Charatify "$app_path/Contents/MacOS/Charatify"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
# Preserve the bundle identity across the product rename (see Resources/Info.plist).
codesign --force --sign - --identifier dev.local.CharacterNotification "$app_path"
printf 'Built: %s\n' "$app_path"
