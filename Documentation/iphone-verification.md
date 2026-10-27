# iPhone verification

Verified locally on October 26, 2026 using Xcode 27.1, CS iPhone Duo (iOS Simulator 27.1), and iPad Pro 13-inch (M5, iPadOS Simulator 27.0), arm64.

## Automated checks

- The iPhone scheme executed six unit tests and one first-run UI test: seven passed, zero failed, zero skipped on each device.
- Unit coverage includes playback failure handling, serialized playback reports, duplicate playlist entry identity, PIN confirmation, collection paging, and touch seek state.
- The UI test launches signed out, opens Add Server, checks the server address field, verifies the address field remains usable after landscape rotation, and retains screenshot attachments.
- Standalone playback, Top Shelf artwork, paging, and PIN policy checks pass.
- iOS and tvOS build-for-testing checks pass.
- SwiftFormat reports no files requiring formatting. SwiftLint regression checking reports 75 existing errors and zero new errors.

## Manual runtime checks

- App launch and server setup render on open and closed Duo layouts.
- Public Jellyfin demo server: connect, username-only authentication, Home artwork and library rows, movie details, MPV playback, skip forward, and close playback.
- Public demo playback continues through partially open and open Duo transitions.
- A user-provided LAN Jellyfin server is discovered automatically, added, and authenticated successfully. Its Home and Continue Watching rows load.
- A movie from the LAN server plays through its HLS transcode with subtitles visible, and continues playing when Duo closes.

Runtime testing found and fixed missing RootCoordinator injection in UIKit-created presentation roots, missing account-refresh notifications, a dismissal race between server setup and sign-in, and the form's rejection of empty passwords. Stream URLs were also removed from playback log metadata because server-generated URLs may contain credentials.

## Website readiness

The isolated ChenAcademy checkout builds four bilingual software pages successfully. Internal page links were checked, and `Documentation/chenacademy-watermelonfin.patch` applies cleanly to the original website checkout. The pages describe source installation without claiming an App Store or TestFlight release. No website deployment was performed. Browser visual verification was unavailable in this environment.

## Remaining release validation

This is local simulator validation, not physical-device or App Store certification. The complete manual matrix in `iphone.md` still includes episode autoplay, duplicate playlist editing against a server, audio/subtitle track switching, failed-stream recovery, PIN/Face ID flows, native-player playback, and extended touch scrubbing. No claim is made that every supported server or codec was exercised.

GitHub access verification shows zero collaborators. Active ruleset `18521833`, "Only MrWeiC can write branches", targets all branches and restricts creation, updates, deletion, and force pushes to the owner, MrWeiC. Separate active ruleset `25924725`, "Main requires pull requests", targets `refs/heads/main`, requires a PR with zero mandatory approvals, blocks deletion and force pushes, and has no bypass actors. CI checks are not yet required because the remote main branch does not contain the prepared workflow.

The optimized unsigned iOS Release archive succeeded after updating Transmission to 2.12.3 and Engine to 2.12.2 and migrating the presentation API. Signing, physical-device validation, and TestFlight upload remain outstanding. See `testflight.md` for prerequisites and beta test notes.
