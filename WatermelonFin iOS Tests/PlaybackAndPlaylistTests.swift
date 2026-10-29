//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
@testable import WatermelonFin_iOS
import XCTest

@MainActor
final class PlaybackAndPlaylistTests: XCTestCase {
    func testMPVProfileDoesNotTranscodeAnamorphicH264() throws {
        let profile = try XCTUnwrap(VideoPlayerType.watermelonfin.codecProfiles.first { $0.codec == "h264" })
        XCTAssertFalse(profile.conditions?.contains { $0.property == .isAnamorphic } ?? false)
        XCTAssertTrue(profile.conditions?.contains { $0.property == .videoRangeType } ?? false)
    }

    func testTrackSelectionPreventsOverlayTimeout() async throws {
        let state = VideoPlayerContainerState(overlayAutoHideInterval: 0.05)
        state.isPresentingOverlay = true
        state.isPresentingSelection = true
        state.timer.poke()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(state.isPresentingOverlay)
        state.isPresentingSelection = false
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(state.isPresentingOverlay)
    }

    func testPlaybackFailureBeforeReadinessDoesNotAutoplay() {
        XCTAssertEqual(PlaybackEndAction.resolve(isError: true, isEOF: false, isStopping: false, isReady: false), .fail)
        XCTAssertEqual(PlaybackEndAction.resolve(isError: false, isEOF: true, isStopping: false, isReady: true), .finish)
        XCTAssertEqual(PlaybackEndAction.resolve(isError: false, isEOF: false, isStopping: false, isReady: true), .ignore)
    }

    func testReportsWaitForTheStartRequestBeforeProgressAndStop() async {
        let queue = PlaybackReportQueue()
        var events: [String] = []
        var continuation: CheckedContinuation<Void, Never>?
        queue.enqueue {
            events.append("start")
            await withCheckedContinuation { continuation = $0 }
        }
        queue.enqueue { events.append("progress") }
        let stopped = queue.enqueue { events.append("stop") }
        while continuation == nil {
            await Task.yield()
        }
        XCTAssertEqual(events, ["start"])
        continuation?.resume()
        await stopped.value
        XCTAssertEqual(events, ["start", "progress", "stop"])
    }

    func testRepeatedMediaKeepsDistinctPlaylistEntryIdentity() {
        var item = BaseItemDto()
        item.id = "movie"
        item.playlistItemID = "first"
        let first = PlaylistEntry(item: item, index: 0)
        item.playlistItemID = "second"
        let second = PlaylistEntry(item: item, index: 1)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.item.id, second.item.id)
    }

    func testNewPINPolicyRequiresConfirmationBeforeSaving() {
        let model = UserLocalSecurityViewModel()
        XCTAssertThrowsError(try model.checkFor(newPolicy: .requirePin))
        XCTAssertThrowsError(try model.checkFor(newPolicy: .requireDeviceAuthentication))
        XCTAssertNoThrow(try model.checkFor(newPolicy: .none))
    }

    func testTwentyItemPagesRemainPageable() {
        XCTAssertTrue(PagingPagePolicy.hasNextPage(receivedCount: 20, pageSize: 20))
        XCTAssertFalse(PagingPagePolicy.hasNextPage(receivedCount: 19, pageSize: 20))
    }
}

@MainActor
final class MobilePlaybackSeekTests: XCTestCase {
    func testSeekUpdatesTheSharedScrubPositionBeforeCompleting() {
        let state = VideoPlayerContainerState()
        let manager = MediaPlayerManager(initialState: .stopped)
        state.scrubbedSeconds.value = .seconds(10)
        state.isScrubbing = true
        MobilePlaybackSeek.finish(position: 90, manager: manager, state: state)
        XCTAssertEqual(state.scrubbedSeconds.value, .seconds(90))
        XCTAssertEqual(manager.seconds, .seconds(90))
        XCTAssertFalse(state.isScrubbing)
    }
}
