#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
: "${APP_VERSION:?Set APP_VERSION (e.g. 0.2.0)}"
export DMG_ONLY="${DMG_ONLY:-0}"
[[ "$DMG_ONLY" == 0 || "$DMG_ONLY" == 1 ]] || { print -u2 'DMG_ONLY must be 0 or 1'; exit 1; }
if [[ "$DMG_ONLY" == 0 ]]; then
    : "${CODE_SIGN_IDENTITY:?Release requires Developer ID Application signing}"
    : "${APPLE_ID:?Release requires notarization: set APPLE_ID}"
    : "${APPLE_TEAM_ID:?Release requires notarization: set APPLE_TEAM_ID}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?Release requires notarization: set APPLE_APP_SPECIFIC_PASSWORD}"
    if [[ "$CODE_SIGN_IDENTITY" != 'Developer ID Application: '* ]]; then
        print -u2 'Release requires CODE_SIGN_IDENTITY="Developer ID Application: ..."'
        exit 1
    fi
fi
export APP_VARIANT=release
export UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-1}"
zsh scripts/build.sh
app_path="$PWD/build/Charatify.app"
output_path="$PWD/build/release"
suffix=""
if [[ "$DMG_ONLY" == 1 ]]; then
    output_path="$PWD/build/dmg"
    suffix="-unnotarized"
fi
mkdir -p "$output_path"
temporary_dir="$(mktemp -d "$output_path/output.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
dmg_name="Charatify-$APP_VERSION$suffix.dmg"
archive_name="Charatify-$APP_VERSION-macos-universal$suffix.zip"
dmg_path="$temporary_dir/$dmg_name"

if [[ "$DMG_ONLY" == 0 ]]; then
    notarize_zip="$temporary_dir/Charatify-notarization.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notarize_zip"
    xcrun notarytool submit "$notarize_zip" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
    xcrun stapler staple "$app_path"
    xcrun stapler validate "$app_path"
    spctl --assess --type execute --verbose "$app_path"
fi

zsh scripts/create-dmg.sh "$app_path" "$dmg_path" Charatify
if [[ "$DMG_ONLY" == 0 ]]; then
    codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$dmg_path"
    xcrun notarytool submit "$dmg_path" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
    spctl --assess --type open --context context:primary-signature --verbose "$dmg_path"
fi
hdiutil verify "$dmg_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$temporary_dir/$archive_name"
(cd "$temporary_dir" && shasum -a 256 "$archive_name" > SHA256SUMS)
mv -f "$dmg_path" "$temporary_dir/$archive_name" "$temporary_dir/SHA256SUMS" "$output_path/"
printf 'Release files: %s\n' "$output_path"
