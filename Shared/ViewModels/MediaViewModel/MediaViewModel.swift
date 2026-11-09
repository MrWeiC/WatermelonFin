//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import OrderedCollections

@MainActor
@Stateful
final class MediaViewModel: ViewModel {

    struct CardData {
        let imageSources: [ImageSource]
        let itemCount: Int?
    }

    private struct CardPreviewData {
        let imageSources: [ImageSource]
        let itemCount: Int?
    }

    private struct CardDataCacheKey: Hashable {
        let serverID: String
        let userID: String
        let mediaTypeID: String
    }

    @CasePathable
    enum Action {
        case refresh

        var transition: Transition {
            .loop(.refreshing)
        }
    }

    enum State {
        case error
        case initial
        case refreshing
    }

    @Published
    private(set) var mediaItems: OrderedSet<MediaType> = []
    @Published
    private(set) var hasLoaded = false
    @Published
    private(set) var cardDataRevision = 0

    private static let cardDataCache = AsyncExpiringCache<CardDataCacheKey, CardPreviewData>(
        timeToLive: 5 * 60
    )

    private let includesLocallyHiddenLibraries: Bool

    init(includesLocallyHiddenLibraries: Bool = false) {
        self.includesLocallyHiddenLibraries = includesLocallyHiddenLibraries
        super.init()
    }

    var selectableLibraries: [BaseItemDto] {
        mediaItems.compactMap(\.libraryItem)
    }

    func mediaItems(in section: MediaType.Section) -> [MediaType] {
        mediaItems.filter { $0.section == section }
    }

    func invalidateCardDataCache() {
        guard let session = currentSession else { return }

        Self.cardDataCache.removeAll {
            $0.serverID == session.server.id && $0.userID == session.user.id
        }
        cardDataRevision += 1
    }

    @Function(\Action.Cases.refresh)
    private func _refresh() async throws {

        mediaItems.removeAll()

        let userViews = try await getUserViews()
        let hiddenLibraryIDs = includesLocallyHiddenLibraries
            ? Set<String>()
            : Set(Defaults[.Customization.Library.hiddenLibraryIDs])
        let media = MediaType.makeMediaItems(
            from: userViews,
            hiddenLibraryIDs: hiddenLibraryIDs,
            showFavorites: !includesLocallyHiddenLibraries && Defaults[.Customization.Library.showFavorites]
        )

        mediaItems.elements = media
        hasLoaded = true
    }

    private func getUserViews() async throws -> [BaseItemDto] {

        let session = try requireSession()
        let parameters = Paths.GetUserViewsParameters(userID: session.user.id)
        let userViewsPath = Paths.getUserViews(parameters: parameters)
        async let userViews = session.client.send(userViewsPath)

        async let excludedLibraryIDs = getExcludedLibraries(session: session)

        // folders has `type = UserView`, but we manually
        // force it to `folders` for better view handling
        return try await (userViews.value.items ?? [])
            .coalesced(property: \.collectionType, with: .folders)
            .intersecting(CollectionType.supportedCases, using: \.collectionType)
            .subtracting(excludedLibraryIDs, using: \.id)
            .map { item in

                if item.type == .userView, item.collectionType == .folders {
                    return item.mutating(\.type, with: .folder)
                }

                return item
            }
    }

    private func getExcludedLibraries(session: UserSession) async throws -> [String] {
        let currentUserPath = Paths.getCurrentUser
        let response = try await session.client.send(currentUserPath)

        return response.value.configuration?.myMediaExcludes ?? []
    }

    func cardData(
        for mediaType: MediaType,
        useRandomImage: Bool
    ) async throws -> CardData {

        let session = try requireSession()

        let cacheKey = CardDataCacheKey(
            serverID: session.server.id,
            userID: session.user.id,
            mediaTypeID: mediaType.id
        )
        let previewData = try await Self.cardDataCache.value(for: cacheKey) {
            try await self.fetchCardPreviewData(
                for: mediaType,
                session: session
            )
        }

        let imageSources: [ImageSource]
        if useRandomImage || mediaType.libraryItem == nil {
            imageSources = previewData.imageSources
        } else if let libraryItem = mediaType.libraryItem {
            imageSources = [libraryItem.imageSource(.primary, maxWidth: 800)] + previewData.imageSources
        } else {
            imageSources = []
        }

        return CardData(
            imageSources: imageSources,
            itemCount: previewData.itemCount
        )
    }

    private func fetchCardPreviewData(
        for mediaType: MediaType,
        session: UserSession
    ) async throws -> CardPreviewData {

        let parentID = mediaType.libraryItem?.id
        let filters: [ItemTrait]? = mediaType == .favorites ? [.isFavorite] : nil

        var parameters = Paths.GetItemsByUserIDParameters()
        parameters.limit = 3
        parameters.isRecursive = true
        parameters.parentID = parentID
        parameters.includeItemTypes = mediaType.previewItemTypes
        parameters.filters = filters
        parameters.sortBy = [ItemSortBy.random.rawValue]

        let request = Paths.getItemsByUserID(userID: session.user.id, parameters: parameters)
        let response = try await session.client.send(request)

        let previewImageSources = (response.value.items ?? [])
            .map { $0.imageSource(.backdrop, maxWidth: 800) }

        return CardPreviewData(
            imageSources: previewImageSources,
            itemCount: response.value.totalRecordCount
        )
    }
}
