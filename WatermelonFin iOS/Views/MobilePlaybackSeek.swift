//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@MainActor
enum MobilePlaybackSeek {
    static func finish(position: Double, manager: MediaPlayerManager, state: VideoPlayerContainerState) {
        guard position.isFinite else { return }
        let target = Duration.seconds(max(0, position))
        // The shared VideoPlayer also observes scrubbing completion; both paths
        // must see the same target rather than the item's original resume point.
        state.scrubbedSeconds.value = target
        manager.seconds = target
        manager.proxy?.setSeconds(target)
        state.isScrubbing = false
        state.timer.poke()
    }
}
