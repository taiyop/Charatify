#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
app_path="$PWD/build/Character Notification.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp .build/release/CharacterNotification "$app_path/Contents/MacOS/CharacterNotification"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - --identifier dev.local.CharacterNotification "$app_path"
printf 'Built: %s\n' "$app_path"
