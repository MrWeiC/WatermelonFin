#!/bin/bash
# Usage: bash Scripts/UITests/run-sign-in-audit.sh <simulator-udid> <new-result-directory>
# Start jellyfin_fixture.py first. Screenshot attachments contain fixture accounts only.
set -euo pipefail
cd "$(dirname "$0")/../.."
device_id=${1:?Simulator UDID required}
result_root=${2:?New output directory required}
if [[ -e "$result_root" ]]; then
    echo "Choose a new result directory; existing evidence will not be overwritten." >&2
    exit 2
fi
python3 - <<'PY'
import json
import urllib.request
with urllib.request.urlopen('http://127.0.0.1:18096/users/preflight/System/Info/Public', timeout=3) as response:
    assert json.load(response)['ServerName'] == 'Preview Media Server', 'Unexpected server on fixture port'
PY
mkdir -p "$result_root"
xcodebuild test -project WatermelonFin.xcodeproj -scheme 'WatermelonFin iOS' \
    -destination "platform=iOS Simulator,id=$device_id" \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    -only-testing:'WatermelonFin iOS UI Tests' \
    -resultBundlePath "$result_root/tests.xcresult" \
    > "$result_root/tests.log" 2>&1
python3 Scripts/UITests/export_screenshots.py "$result_root/tests.xcresult" "$result_root/screenshots"
xcrun xcresulttool get test-results summary --path "$result_root/tests.xcresult" > "$result_root/summary.json"
echo "Audit results: $result_root"
