//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@main
struct PlaybackReliabilityTests {
    @MainActor
    static func main() async {
        // A load error must reach the UI even before the renderer becomes ready.
        precondition(PlaybackEndAction.resolve(isError: true, isEOF: false, isStopping: false, isReady: false) == .fail)
        precondition(PlaybackEndAction.resolve(isError: false, isEOF: true, isStopping: false, isReady: true) == .finish)
        precondition(PlaybackEndAction.resolve(isError: false, isEOF: false, isStopping: false, isReady: true) == .ignore)
        precondition(PlaybackEndAction.resolve(isError: true, isEOF: false, isStopping: true, isReady: true) == .ignore)

        let queue = PlaybackReportQueue()
        var events: [String] = []
        var releaseStart: CheckedContinuation<Void, Never>?
        let start = queue.enqueue {
            events.append("start")
            await withCheckedContinuation { releaseStart = $0 }
        }
        let progress = queue.enqueue { events.append("progress") }
        let stop = queue.enqueue { events.append("stop") }
        while releaseStart == nil {
            await Task.yield()
        }
        precondition(events == ["start"], "Reports must wait for the previous request")
        releaseStart?.resume()
        await start.value
        await progress.value
        await stop.value
        precondition(events == ["start", "progress", "stop"])
        print("Playback reliability checks passed")
    }
}
