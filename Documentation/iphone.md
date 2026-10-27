# WatermelonFin on iPhone

The iPhone target shares the current Jellyfin session, persistence, library, playlist, and playback models with Apple TV. It adds native touch browsing and playback controls.

## Run locally

1. Open `WatermelonFin.xcodeproj` in a current Xcode installation.
2. Select the **WatermelonFin iOS** scheme and an installed iPhone simulator. Swift packages resolve automatically.
3. Press Run. For a physical iPhone, select your own development team under Signing & Capabilities first.
4. Add your Jellyfin server, then sign in with your server account.

The project targets iOS 17.5 and tvOS 17.5 or later. CoreStore is pinned to 9.2.0 because 9.3.0 fails to compile a typed-throws overload with the local Xcode 27.1 toolchain. Get is explicitly linked because shared code imports its request/client types directly.

## Validate

```sh
bash Scripts/Checks/run-reliability-checks.sh
python3 Scripts/Checks/check-swiftlint-regressions.py origin/main
swiftformat . --lint --config .swiftformat
xcodebuild test -project WatermelonFin.xcodeproj \
  -scheme "WatermelonFin iOS" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

Replace the destination with a simulator installed on your Mac (`xcrun simctl list devices available`). The scheme includes unit tests and a first-run UI test. The UI test launches signed out and captures the server setup screen; use a dedicated test simulator.

For CS iPhone Duo, select **WatermelonFin iOS → CS iPhone Duo** in Xcode and choose Product → Test. Device Hub provides Closed, Partially Open, and Open posture controls. See [verification results](iphone-verification.md) for the checks actually performed.

## Feature coverage

- Saved servers/accounts, Quick Connect, token recovery, server-address recovery, local PIN and device authentication.
- Home/resume/next-up, paginated libraries and filters, search, movie/series/episode details, cast, trailers, favorite/watched actions, and permission-gated item actions.
- Server-owned ordered playlists with duplicate-entry identity, creation, membership editing, and pagination.
- MPV and native playback, touch seeking, audio/subtitles, speed, quality preferences, chapters/info, episode queues and autoplay.
- Live channels/programs and the existing app, profile, library, player and diagnostic settings.

Top Shelf and remote focus navigation remain specific to Apple TV. The old upstream iOS administration/download UI is not exposed by this target.

## Manual playback checks

Use a Jellyfin test account and verify sign-in/out, a >20-item collection, a playlist containing the same movie twice, episode autoplay, a long slider drag, seek/resume, audio/subtitle switching, failed-stream recovery, and rotation during playback. Confirm PIN cancellation does not change protection and Face ID is required before modifying a protected account.

## Website

The isolated ChenAcademy checkout is under `docs/chenacademy-website`. Its bilingual software listing and WatermelonFin install/support pages are prepared there. The website build is `npm run build:software`; changes are not published automatically. A patch is provided with this change for integration into the website repository.
