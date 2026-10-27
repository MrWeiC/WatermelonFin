#!/bin/bash
# MPVKit-GPL's generated framework plist advertises 12.0 even when Xcode
# links its binary for our 17.5 deployment target. Match the actual Mach-O.
set -euo pipefail
case "${PLATFORM_NAME:-}" in iphoneos|appletvos) ;; *) exit 0 ;; esac
framework="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/MPVKit.framework"
[[ -f "$framework/Info.plist" && -f "$framework/MPVKit" ]] || { echo 'error: Embedded MPVKit framework is missing'; exit 1; }
minimum=$(xcrun vtool -show-build "$framework/MPVKit" | awk '$1 == "minos" {print $2; exit}')
[[ -n "$minimum" ]] || { echo 'error: Cannot determine MPVKit binary minimum OS'; exit 1; }
current=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$framework/Info.plist")
if [[ "$current" != "$minimum" ]]; then
    /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $minimum" "$framework/Info.plist"
    if [[ "${CODE_SIGNING_ALLOWED:-NO}" == YES && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
        /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --preserve-metadata=identifier,entitlements,flags "$framework"
    fi
fi
echo "MPVKit MinimumOSVersion: $minimum"
