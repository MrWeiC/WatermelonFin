# Crystal watermelon launch animation

The approved, symmetrically cropped movies are bundled offline in
`Shared/Resources/Launch`. The portrait crop (404 × 720) is used when an iPhone
opens in portrait. iPad, landscape iPhone, and Apple TV use the wider crop
(768 × 720). Both are H.264 at 60 fps, about four seconds long, with no audio
track. They are the accepted generated artwork; the generated five-piece
sequence has not been redrawn as six pieces.

`Shared/Components/WatermelonLaunchContainer.swift` wraps the existing app root
on both targets. The root initializes behind the overlay. Playback is aspect-fit
with safe margins and never stretches or loops. Rotating during playback retains
the initially chosen movie and playback position. Backgrounding dismisses the
overlay permanently for that window. Completion or playback failure dismisses
it, with a five-second maximum wait. The player is detached on removal.

The first-frame poster covers decoder startup. Reduce Motion displays the
last-frame brand poster for 0.3 seconds instead of playing a movie. No player
controls or TV focusable elements are introduced. Ordinary media-loading UI is
unchanged.

## Validation

Run `python3 Scripts/Checks/ValidateLaunchVideos.py` to check that both movies
decode, contain no audio, have the expected crop and duration, and match their
first/last-frame posters. Requires ffmpeg and ffprobe.

Build the `WatermelonFin iOS` and `WatermelonFin tvOS` schemes. Check that each
app bundle contains the six `watermelon-launch-*` resources. The existing iOS
`FirstRunTests` exercises launch dismissal, usable server setup, background /
foreground without replay, and rotation on iPhone and iPad.

For visual review, cold-launch on each device family, check the centered video
and wordmark, then verify that the real root screen takes focus after dismissal.
Also verify a cold launch with Reduce Motion and backgrounding during the movie.
