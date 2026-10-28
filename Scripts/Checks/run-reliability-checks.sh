#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/watermelonfin-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -module-cache-path "$check_dir/modules" -parse-as-library \
  Shared/Objects/MediaPlayerManager/PlaybackEndAction.swift \
  Shared/Objects/MediaPlayerManager/PlaybackReportQueue.swift \
  Scripts/Checks/PlaybackReliabilityTests.swift -o "$check_dir/playback"
"$check_dir/playback"
swiftc -module-cache-path "$check_dir/modules" -parse-as-library \
  Shared/Services/TopShelfArtworkStore.swift \
  Scripts/Checks/TopShelfArtworkTests.swift -o "$check_dir/artwork"
"$check_dir/artwork"
swiftc -module-cache-path "$check_dir/modules" -parse-as-library \
  Shared/ViewModels/LibraryViewModel/PagingPagePolicy.swift \
  Scripts/Checks/PagingPolicyTests.swift -o "$check_dir/paging"
"$check_dir/paging"

swiftc -module-cache-path "$check_dir/modules" -parse-as-library \
  Shared/Objects/LocalPINPolicy.swift Scripts/Checks/LocalPINPolicyTests.swift -o "$check_dir/pin"
"$check_dir/pin"

swiftc -module-cache-path "$check_dir/modules" -parse-as-library \
  Shared/ServerDiscovery/ServerAddressInput.swift Scripts/Checks/ServerAddressPolicyTests.swift -o "$check_dir/server-address"
"$check_dir/server-address"
