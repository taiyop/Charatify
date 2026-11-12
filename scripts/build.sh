#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export APP_VARIANT="${APP_VARIANT:-dev}"
export DMG_ONLY="${DMG_ONLY:-0}"
[[ "$DMG_ONLY" == 0 || "$DMG_ONLY" == 1 ]] || { print -u2 'DMG_ONLY must be 0 or 1'; exit 1; }
case "$APP_VARIANT" in
    dev)
        app_path="$PWD/build/Charatify Dev.app"
        identity="${DEV_CODE_SIGN_IDENTITY:--}"
        configuration=debug
        ;;
    release)
        app_path="$PWD/build/Charatify.app"
        if [[ "$DMG_ONLY" == 1 ]]; then
            identity=-
        else
            identity="${CODE_SIGN_IDENTITY:?Release builds require a Developer ID Application identity}"
            if [[ "$identity" != 'Developer ID Application: '* ]]; then
                print -u2 'Release builds require CODE_SIGN_IDENTITY="Developer ID Application: ..."'
                exit 1
            fi
        fi
        configuration=release
        ;;
    *) print -u2 'APP_VARIANT must be dev or release'; exit 1 ;;
esac
build_args=(-c "$configuration")
if [[ "${UNIVERSAL_BUILD:-0}" == "1" ]]; then
    build_args+=(--arch arm64 --arch x86_64)
fi
swift build "${build_args[@]}"
bin_path="$(swift build "${build_args[@]}" --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
cp "$bin_path/Charatify" "$app_path/Contents/MacOS/Charatify"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
python3 scripts/configure-update.py "$app_path/Contents/Info.plist"
if [[ "$APP_VARIANT" == dev ]]; then
    swift scripts/make-dev-icon.swift "$PWD/build/CharatifyDev.iconset"
    iconutil -c icns "$PWD/build/CharatifyDev.iconset" -o "$app_path/Contents/Resources/CharatifyDev.icns"
fi

# ditto preserves the symlinks and helpers required by Sparkle's framework.
framework="$app_path/Contents/Frameworks/Sparkle.framework"
rm -rf "$framework"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app_path/Contents/Resources/Sparkle-LICENSE.txt"

sign_args=(--force --sign "$identity")
if [[ "$identity" != "-" ]]; then
    sign_args+=(--options runtime)
    if [[ "$APP_VARIANT" == release ]]; then sign_args+=(--timestamp); fi
elif [[ "$APP_VARIANT" == dev ]]; then
    print 'Dev build uses ad-hoc signing; set DEV_CODE_SIGN_IDENTITY to an Apple Development identity to retain permissions across rebuilds.'
else
    print 'DMG-only build uses ad-hoc signing and has no notarization or update checking.'
fi
# Sign inside out. --deep signing would incorrectly share XPC entitlements.
codesign "${sign_args[@]}" "$framework/Versions/B/XPCServices/Installer.xpc"
codesign "${sign_args[@]}" --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
codesign "${sign_args[@]}" "$framework/Versions/B/Autoupdate"
codesign "${sign_args[@]}" "$framework/Versions/B/Updater.app"
codesign "${sign_args[@]}" "$framework"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
codesign "${sign_args[@]}" --identifier "$bundle_id" "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Built: %s\n' "$app_path"
