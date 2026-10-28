# Watermelon loading animation

Approved user intent: a Fruit Ninja inspired watermelon slice that becomes a play button on iPhone and iPad. User accepted the recommendation: a full launch sequence and a shorter playback-loading loop, then explicitly requested Astra create the animation.

Approach: native SwiftUI vector animation, delivered by Astra. This avoids adding a movie/Lottie dependency and scales across phone, tablet and folding layouts. Existing artwork supplies the red/green brand cues. A prerendered video was considered but would add assets and make accessibility and sizing less flexible.

Cold launch overlays the existing root view while it initializes, for approximately 1.5 seconds, then fades away automatically. Returning from background does not replay. A whole melon is slashed, separates into a slice, and resolves into a play triangle. Playback loading uses a compact loop and keeps the existing cancel action. Real playback is never delayed to finish an animation. Reduce Motion uses static artwork and a short fade; no sound, permission, dependency or tvOS change.

Implementation decisions delegated to us: precise geometry/easing, responsive sizing and color shades. Root and player integration stay separate from the drawing component. Verify actual Xcode builds, simulator display and first-run interaction after the overlay dismisses. A new TestFlight build is required before this appears in the installed beta.

## Visual revision from user feedback

The first flat vector version was rejected: it ended at an anonymous white play triangle and did not convey WatermelonFin or the existing dimensional crystal/gloss finish. Revised requirement: end on the exact approved red beveled watermelon artwork with its inset play symbol, with the actual red/green WatermelonFin wordmark visible. Preserve the material, seeds, rind facets and silhouette of the current icon. Cutting action and restrained specular movement should support that artwork. No white triangle replacement. A slightly longer bounded launch (approximately 2.1 seconds including a recognizable final hold) is acceptable as an implementation choice; playback keeps the actual mark in a gentle loop. Show the revised rendered preview before any TestFlight release.

## Split-and-slice revision

The user rejected the gradient/reveal transition and specified a physical sequence: begin with a large whole watermelon; split through its center into two halves; turn the halves to expose red flesh; make sharp cuts into six wedges; rotate one selected wedge into the existing WatermelonFin icon. “红心儿” is interpreted as red watermelon flesh. Preserve the crystalline material and finish on the exact existing brand mark and WatermelonFin wordmark. Use explicit separation and rotation rather than fading between fruit and logo. Astra continues the implementation. Approximately 3.8 seconds is an implementation choice to make the actions readable; show the actual-code preview before release.
