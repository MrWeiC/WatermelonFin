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
final class MainTabViewTabsTests: XCTestCase {

    private func library(
        id: String,
        name: String,
        collectionType: CollectionType
    ) -> BaseItemDto {
        var item = BaseItemDto()
        item.id = id
        item.name = name
        item.type = .collectionFolder
        item.collectionType = collectionType
        return item
    }

    func testTVOSTabsIncludeLibrariesBetweenMoviesAndSearch() {
        let tabs = TabItem.tvOSTabs

        XCTAssertEqual(
            tabs.map(\.title),
            [
                L10n.home,
                L10n.tv,
                L10n.movies,
                L10n.libraries,
                L10n.search,
                L10n.settings,
            ]
        )
        XCTAssertEqual(tabs.first { $0.title == L10n.libraries }?.id, "libraries")
        XCTAssertEqual(tabs.first { $0.title == L10n.libraries }?.systemImage, "rectangle.stack.fill")
    }

    func testLibraryAndCollectionViewsUseSeparateSections() {
        let movies = library(id: "movies", name: "Movies", collectionType: .movies)
        let collections = library(id: "collections", name: "Collections", collectionType: .boxsets)

        let mediaItems = MediaViewModel.MediaType.makeMediaItems(
            from: [movies, collections],
            hiddenLibraryIDs: [],
            showFavorites: false
        )

        XCTAssertEqual(mediaItems.map(\.section), [.libraries, .collections])
        XCTAssertEqual(mediaItems.map(\.id), ["movies", "collections"])
    }

    func testFourPrimaryMediaTypesAppearInLibrariesSection() {
        let mediaItems = MediaViewModel.MediaType.makeMediaItems(
            from: [
                library(id: "movies", name: "Movies", collectionType: .movies),
                library(id: "shows", name: "Shows", collectionType: .tvshows),
                library(id: "music", name: "Music", collectionType: .music),
            ],
            hiddenLibraryIDs: [],
            showFavorites: false
        )

        XCTAssertEqual(mediaItems.map(\.id), ["movies", "shows", "music"])
        XCTAssertTrue(mediaItems.allSatisfy { $0.section == .libraries })
    }

    func testLiveTVLibrariesAreNotShown() {
        let mediaItems = MediaViewModel.MediaType.makeMediaItems(
            from: [
                library(id: "movies", name: "Movies", collectionType: .movies),
                library(id: "live-tv", name: "Live TV", collectionType: .livetv),
            ],
            hiddenLibraryIDs: [],
            showFavorites: false
        )

        XCTAssertEqual(mediaItems.map(\.id), ["movies"])
        XCTAssertFalse(CollectionType.supportedCases.contains(.livetv))
    }

    func testHiddenLibrariesAreRemovedWithoutHidingOtherLibraries() {
        let movies = library(id: "movies", name: "Movies", collectionType: .movies)
        let shows = library(id: "shows", name: "Shows", collectionType: .tvshows)

        let mediaItems = MediaViewModel.MediaType.makeMediaItems(
            from: [movies, shows],
            hiddenLibraryIDs: ["movies"],
            showFavorites: true
        )

        XCTAssertEqual(mediaItems.map(\.id), ["favorites", "shows"])
    }

    func testSupportedLibraryTypesIncludePlayableMusicPlaylistsAndTrailers() {
        XCTAssertTrue(CollectionType.supportedCases.contains(.music))
        XCTAssertTrue(CollectionType.supportedCases.contains(.playlists))
        XCTAssertTrue(CollectionType.supportedCases.contains(.trailers))
        XCTAssertFalse(CollectionType.supportedCases.contains(.books))
        XCTAssertFalse(CollectionType.supportedCases.contains(.photos))
    }

    func testLibraryTypesMapToTheirBrowsableItemTypes() {
        XCTAssertEqual(
            library(id: "music", name: "Music", collectionType: .music).supportedItemTypes,
            [.musicAlbum]
        )
        XCTAssertEqual(
            library(id: "playlists", name: "Playlists", collectionType: .playlists).supportedItemTypes,
            [.playlist]
        )
        XCTAssertEqual(
            library(id: "trailers", name: "Trailers", collectionType: .trailers).supportedItemTypes,
            [.trailer]
        )
        XCTAssertEqual(
            library(id: "collections", name: "Collections", collectionType: .boxsets).supportedItemTypes,
            [.boxSet]
        )
    }

    func testCollectionLibraryUsesStableBoxSetQuery() throws {
        let collections = try XCTUnwrap(
            MediaViewModel.MediaType(
                userView: library(id: "collections", name: "Collections", collectionType: .boxsets)
            )
        )

        XCTAssertEqual(collections.libraryFilters.itemTypes, [.boxSet, .userView])

        let movies = try XCTUnwrap(
            MediaViewModel.MediaType(
                userView: library(id: "movies", name: "Movies", collectionType: .movies)
            )
        )
        XCTAssertEqual(movies.libraryFilters, .default)
    }

    func testLibraryFeatureChineseTranslations() {
        XCTAssertEqual(L10n.libraries, "媒体库")
        XCTAssertEqual(L10n.hiddenLibraries, "隐藏媒体库")
        XCTAssertEqual(L10n.noLibrariesFound, "未找到媒体库")
    }

    func testDefaultPlaylistLibraryNameIsLocalized() {
        let playlists = library(id: "playlists", name: "Playlists", collectionType: .playlists)

        XCTAssertEqual(playlists.localizedCollectionDisplayTitle, PlaylistL10n.playlists)
    }

    func testCustomPlaylistLibraryNameIsPreserved() {
        let familyPicks = library(id: "playlists", name: "Family Picks", collectionType: .playlists)

        XCTAssertEqual(familyPicks.localizedCollectionDisplayTitle, "Family Picks")
    }
}
