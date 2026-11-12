#!/bin/zsh
# Local installation testing always uses the separate Dev identity and storage.
set -euo pipefail
cd "${0:A:h:h}"
export APP_VARIANT=dev
zsh scripts/build.sh
mkdir -p "$PWD/build/dev-dmg"
temporary_dir="$(mktemp -d "$PWD/build/dev-dmg/output.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
zsh scripts/create-dmg.sh "$PWD/build/Charatify Dev.app" "$temporary_dir/Charatify-Dev.dmg" 'Charatify Dev'
mv -f "$temporary_dir/Charatify-Dev.dmg" "$PWD/build/dev-dmg/Charatify-Dev.dmg"
printf 'Development DMG: %s\n' "$PWD/build/dev-dmg/Charatify-Dev.dmg"
