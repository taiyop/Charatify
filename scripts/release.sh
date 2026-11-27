#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
: "${APP_VERSION:?Set APP_VERSION (e.g. 0.2.0)}"
build_version="${APP_BUILD_VERSION:-$APP_VERSION}"
export DMG_ONLY="${DMG_ONLY:-0}"
[[ "$DMG_ONLY" == 0 || "$DMG_ONLY" == 1 ]] || { print -u2 'DMG_ONLY must be 0 or 1'; exit 1; }
if [[ "$DMG_ONLY" == 0 ]]; then
    : "${SPARKLE_PUBLIC_ED_KEY:?Set the public Ed25519 key}"
    : "${RELEASE_DOWNLOAD_URL:?Set the HTTPS URL prefix for release assets}"
    : "${CODE_SIGN_IDENTITY:?Release requires Developer ID Application signing}"
    : "${APPLE_ID:?Release requires notarization: set APPLE_ID}"
    : "${APPLE_TEAM_ID:?Release requires notarization: set APPLE_TEAM_ID}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?Release requires notarization: set APPLE_APP_SPECIFIC_PASSWORD}"
    if [[ "$CODE_SIGN_IDENTITY" != 'Developer ID Application: '* ]]; then
        print -u2 'Release requires CODE_SIGN_IDENTITY="Developer ID Application: ..."'
        exit 1
    fi
    if [[ "$RELEASE_DOWNLOAD_URL" != https://* ]]; then
        print -u2 'RELEASE_DOWNLOAD_URL must use HTTPS'
        exit 1
    fi
fi
export APP_VARIANT=release
export UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-1}"
zsh scripts/build.sh
app_path="$PWD/build/Charatify.app"
if [[ "$DMG_ONLY" == 1 ]]; then
    # Keep unnotarized archives outside the directory used by generate_appcast.
    output_path="$PWD/build/dmg"
    mkdir -p "$output_path"
    temporary_dir="$(mktemp -d "$output_path/output.XXXXXX")"
    trap 'rm -rf "$temporary_dir"' EXIT
    dmg_name="Charatify-$APP_VERSION-unnotarized.dmg"
    zsh scripts/create-dmg.sh "$app_path" "$temporary_dir/$dmg_name" Charatify
    hdiutil verify "$temporary_dir/$dmg_name"
    mv -f "$temporary_dir/$dmg_name" "$output_path/$dmg_name"
    printf 'DMG only (ad-hoc signed, not notarized; updates disabled): %s\n' "$output_path/$dmg_name"
    exit 0
fi
updates_path="$PWD/build/updates"
mkdir -p "$updates_path"
dmg_path="$updates_path/Charatify-$APP_VERSION.dmg"
if [[ -e "$dmg_path" ]]; then
    print -u2 "Archive already exists: $dmg_path. Use a new version or a clean build directory."
    exit 1
fi

# Both app and DMG must be notarized before the signed feed can be generated.
notarize_zip="$PWD/build/Charatify-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notarize_zip"
xcrun notarytool submit "$notarize_zip" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
xcrun stapler staple "$app_path"

zsh scripts/create-dmg.sh "$app_path" "$dmg_path" Charatify
codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$dmg_path"
xcrun notarytool submit "$dmg_path" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$app_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type execute --verbose "$app_path"
spctl --assess --type open --context context:primary-signature --verbose "$dmg_path"

temporary_dir="$(mktemp -d "$updates_path/appcast.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
ln "$dmg_path" "$temporary_dir/${dmg_path:t}"
download_prefix="${RELEASE_DOWNLOAD_URL%/}/"
appcast_args=(--download-url-prefix "$download_prefix" --maximum-deltas 0)
if [[ "$APP_VERSION" == *-nightly.* ]]; then
    appcast_args+=(--channel nightly)
fi
appcast_args+=("$temporary_dir")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    # The private key stays off the command line and out of logs/files.
    printf '%s' "$SPARKLE_PRIVATE_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast --ed-key-file - "${appcast_args[@]}"
else
    .build/artifacts/sparkle/Sparkle/bin/generate_appcast --account Charatify "${appcast_args[@]}"
fi
appcast="$temporary_dir/appcast.xml"
if [[ "$APP_VERSION" == *-nightly.* ]]; then
    python3 scripts/validate-appcast.py set-nightly-label "$appcast" "$build_version" "$APP_VERSION"
fi
python3 scripts/validate-appcast.py validate "$appcast" "$build_version" "$APP_VERSION" \
    --archive "$dmg_path" --public-key "$SPARKLE_PUBLIC_ED_KEY" --download-prefix "$download_prefix"
mv -f "$appcast" "$updates_path/appcast.xml"
printf 'Release files: %s\n' "$updates_path"
