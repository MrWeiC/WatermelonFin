# Watermelon loading animation

Approved user intent: a Fruit Ninja inspired watermelon slice that becomes a play button on iPhone and iPad. User accepted the recommendation: a full launch sequence and a shorter playback-loading loop, then explicitly requested Astra create the animation.

Approach: native SwiftUI vector animation, delivered by Astra. This avoids adding a movie/Lottie dependency and scales across phone, tablet and folding layouts. Existing artwork supplies the red/green brand cues. A prerendered video was considered but would add assets and make accessibility and sizing less flexible.

Cold launch overlays the existing root view while it initializes, for approximately 1.5 seconds, then fades away automatically. Returning from background does not replay. A whole melon is slashed, separates into a slice, and resolves into a play triangle. Playback loading uses a compact loop and keeps the existing cancel action. Real playback is never delayed to finish an animation. Reduce Motion uses static artwork and a short fade; no sound, permission, dependency or tvOS change.

Implementation decisions delegated to us: precise geometry/easing, responsive sizing and color shades. Root and player integration stay separate from the drawing component. Verify actual Xcode builds, simulator display and first-run interaction after the overlay dismisses. A new TestFlight build is required before this appears in the installed beta.
