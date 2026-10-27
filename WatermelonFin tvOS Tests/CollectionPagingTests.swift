//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
@testable import WatermelonFin_tvOS
import XCTest

@MainActor
final class CollectionPagingTests: XCTestCase {
    private final class Library: PagingLibraryViewModel<BaseItemDto> {
        override func get(page: Int) async throws -> [BaseItemDto] {
            guard page < 2 else { return [] }
            return (0 ..< 20).map { index in
                var item = BaseItemDto()
                item.id = "\(page)-\(index)"
                return item
            }
        }
    }

    func testTwentyItemPagesCanLoadTheTwentyFirstItem() async throws {
        let library = Library(pageSize: 20)
        try await library.refresh()
        XCTAssertTrue(library.hasNextPage)
        try await library.getNextPage()
        XCTAssertEqual(library.elements.count, 40)
    }

    func testRefreshClearsPendingPaginationFlag() {
        let library = Library(pageSize: 20)
        _ = library.respond(to: .getNextPage)
        XCTAssertTrue(library.backgroundStates.contains(.gettingNextPage))
        _ = library.respond(to: .refresh)
        XCTAssertFalse(library.backgroundStates.contains(.gettingNextPage))
    }

    func testRepeatedPlaylistVideosHaveDistinctEntryIdentity() {
        var first = BaseItemDto()
        first.id = "same-movie"
        first.playlistItemID = "entry-1"
        var second = first
        second.playlistItemID = "entry-2"
        XCTAssertNotEqual(PlaylistEntry(item: first, index: 0).id, PlaylistEntry(item: second, index: 1).id)
    }
}
