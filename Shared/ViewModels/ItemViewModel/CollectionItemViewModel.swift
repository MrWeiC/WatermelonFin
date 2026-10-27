//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI
import OrderedCollections

final class CollectionItemViewModel: ItemViewModel {

    @ObservedPublisher
    var sections: OrderedDictionary<BaseItemKind, ItemLibraryViewModel>

    let playlistEntries: PlaylistEntriesViewModel?

    private let itemCollection: ItemTypeCollection

    override init(item: BaseItemDto) {
        self.playlistEntries = item.type == .playlist ? PlaylistEntriesViewModel(playlist: item) : nil
        self.itemCollection = ItemTypeCollection(
            parent: item,
            itemTypes: BaseItemKind.supportedCases
                .appending(.audio)
                .appending(.episode)
                .appending(.person)
        )
        self._sections = ObservedPublisher(
            wrappedValue: [:],
            observing: itemCollection.$elements
        )

        super.init(item: item)
    }

    // MARK: - Override Response

    override func respond(to action: ItemViewModel.Action) -> ItemViewModel.State {

        switch action {
        case .refresh, .backgroundRefresh:
            if let playlistEntries {
                playlistEntries.refresh()
            } else {
                itemCollection.send(.refresh)
            }
        default: ()
        }

        return super.respond(to: action)
    }

    // TODO: possibly multiple items, for image source fallbacks
    func randomItem() -> BaseItemDto? {
        if let playlistEntries { return playlistEntries.entries.randomElement()?.item }

        // Try to exclude episodes if possible

        if itemCollection.elements.elements.count == 1 {
            return itemCollection.elements.elements.first?.value.elements.first
        }

        return itemCollection.elements
            .elements
            .shuffled()
            .filter { $0.key != .episode }
            .randomElement()?
            .value
            .elements
            .randomElement()
    }

    func removeFromPlaylist(_ entry: BaseItemDto) async throws {
        guard item.type == .playlist,
              let playlistID = item.id,
              let entryID = entry.playlistItemID
        else {
            throw ErrorMessage(L10n.unknownError)
        }

        let session = try requireSession()
        let request = Paths.removeItemFromPlaylist(
            playlistID: playlistID,
            entryIDs: [entryID]
        )
        _ = try await session.client.send(request)

        await MainActor.run {
            if let playlistEntries {
                playlistEntries.refresh()
            } else {
                itemCollection.send(.refresh)
            }
        }
    }
}
