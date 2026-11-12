#!/bin/zsh
set -euo pipefail
app_path="${1:?Pass an app bundle}"
dmg_path="${2:?Pass a destination DMG}"
volume_name="${3:?Pass a volume name}"
[[ -d "$app_path/Contents" ]] || { print -u2 'App bundle does not exist'; exit 1; }
[[ ! -e "$dmg_path" ]] || { print -u2 "Archive already exists: $dmg_path"; exit 1; }
mkdir -p "${dmg_path:h}"
stage="$(mktemp -d "${dmg_path:h}/dmg-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app_path" "$stage/${app_path:t}"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "$volume_name" -srcfolder "$stage" -fs APFS -format ULFO "$dmg_path"
