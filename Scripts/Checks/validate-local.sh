#!/bin/bash
# Run from any directory. Requires Xcode and installed iOS/tvOS simulators.
set -euo pipefail
cd "$(dirname "$0")/../.."
mode=${1:---all}
case "$mode" in --all|--quick) ;; *) echo "Usage: $0 [--all|--quick]" >&2; exit 2 ;; esac
python3 Scripts/Checks/ValidateLocalizations.py
bash Scripts/Checks/run-reliability-checks.sh
check_cache=$(mktemp -d "${TMPDIR:-/tmp}/watermelonfin-validation-cache.XXXXXX")
trap 'rm -rf "$check_cache"' EXIT
swift -module-cache-path "$check_cache" Scripts/Checks/ValidateATSConfiguration.swift
git diff --check
if [[ "$mode" == --quick ]]; then exit 0; fi
result_root=${WATERMELONFIN_RESULTS_DIR:-"${TMPDIR:-/tmp}/watermelonfin-validation-$(date +%Y%m%d-%H%M%S)"}
mkdir -p "$result_root"
echo "Results: $result_root"
for profile in iPhone iPad AppleTV; do
    signing_args=(CODE_SIGNING_ALLOWED=NO)
    if [[ "$profile" == AppleTV ]]; then
        # Keychain integration tests need a signed simulator host.
        signing_args=()
        scheme='WatermelonFin tvOS Tests'; runtime=tvOS; device='Apple TV'
    else
        scheme='WatermelonFin iOS'; runtime=iOS; device="$profile"
    fi
    device_id=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
runtime,device=sys.argv[1:]
for key,devices in reversed(list(json.load(sys.stdin)["devices"].items())):
    if runtime not in key: continue
    for item in devices:
        if device in item["name"]:
            print(item["udid"]); sys.exit(0)
sys.exit("No available "+device+" simulator; install one in Xcode Settings > Components")
' "$runtime" "$device")
    xcodebuild test -project WatermelonFin.xcodeproj -scheme "$scheme" \
        -destination "platform=$runtime Simulator,id=$device_id" \
        -resultBundlePath "$result_root/$profile.xcresult" "${signing_args[@]}" \
        2>&1 | tee "$result_root/$profile.log"
done
echo "All local checks passed. Results: $result_root"
