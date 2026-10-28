# Watermelon Loading Implementation Plan

Goal: add an accessible native launch and playback loading animation to iPhone/iPad.
Architecture: Astra owns WatermelonLoadingAnimation, root agent integrates it at the iOS WindowGroup and WatermelonPlaybackLoadingView. Existing root starts immediately behind the overlay. SwiftUI task cancellation owns lifecycle.
Tech Stack: SwiftUI, iOS/iPadOS 17.5+, existing project, no new dependencies.
Spec: docs/superpowers/specs/2026-10-27-watermelon-loading-design.md

## Constraints and review focus
- Preserve TV loading and player cancellation.
- Overlay must disappear automatically and not replay on foreground.
- Reduce Motion must avoid slicing/rotation.
- Phone/tablet rotation must not clip or restart the animation.
- Playback can finish loading immediately; animation must never hold it back.

## Tasks
- [x] Astra creates reusable vector drawing and bounded launch/compact-loop modes.
- [x] Integrate launch overlay, localized accessible loading status, and playback loader under WATERMELONFIN_PHONE.
- [x] Verify Xcode build and first-run simulator flow; visually inspect drawing on phone/tablet where available.
- [x] Review diff, run local checks and create a focused PR. Do not merge without user instruction.

## Verification evidence

Xcode 27.1 built and ran the iOS app successfully. The existing first-run UI test, extended to cover splash dismissal and background/reactivation without replay, passed on CS iPhone Duo (18.971 seconds) and iPad Pro 13-inch (M5, 17.160 seconds), with zero failures in each UI test run. The test also opens server setup and verifies portrait/landscape interaction. Local playback, Top Shelf, paging, PIN and ATS checks passed.

The exact Canvas drawing methods were rendered with SwiftUI ImageRenderer to produce `docs/watermelon-loading-animation.gif`; the image is a rendering preview, not a simulator recording. Reduce Motion branch was code-reviewed but has not been separately exercised with the system setting. No live-server playback was performed for this visual change. No new TestFlight build has been uploaded for the animation.

Astra final integration review caught the previously unused loading view. Both actual playback paths now use the mobile animation: MPV keeps its initializing container mounted beneath a loadingItem overlay, and native playback replaces its waiting spinner. MPV underlying controls are hidden from VoiceOver while the loading overlay is present. Cancel still uses normal route dismissal and teardown.

The older tvOS LoadingView is excluded from the iOS target; a dedicated iOS WatermelonPlaybackLoadingView now supplies the shared waiting screen. tvOS source remains unchanged.
