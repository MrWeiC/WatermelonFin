//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Playlist membership is ordered and can contain the same media item more than once.
/// Its identity must therefore come from the playlist entry, not the media item.
struct PlaylistEntry: Identifiable {
    let id: String
    let item: BaseItemDto

    init(item: BaseItemDto, index: Int) {
        self.id = item.playlistItemID ?? "\(index)-\(item.id ?? "unknown")"
        self.item = item
    }
}

final class PlaylistEntriesViewModel: ViewModel {
    @Published
    private(set) var entries: [PlaylistEntry] = []
    @Published
    private(set) var isLoading = false
    @Published
    private(set) var hasNextPage = true
    @Published
    private(set) var error: Error?

    private let playlist: BaseItemDto
    private let pageSize = 50
    private var nextIndex = 0
    private var generation = UUID()
    private var task: Task<Void, Never>?

    init(playlist: BaseItemDto) {
        self.playlist = playlist
        super.init()
    }

    @MainActor
    func refresh() {
        task?.cancel()
        generation = UUID()
        entries = []
        nextIndex = 0
        hasNextPage = true
        isLoading = false
        loadNextPage()
    }

    @MainActor
    func loadNextPage() {
        guard !isLoading, hasNextPage else { return }
        isLoading = true
        error = nil
        let generation = generation
        let startIndex = nextIndex
        task = Task { @MainActor in
            do {
                let session = try requireSession()
                guard let id = playlist.id else { throw ErrorMessage(L10n.unknownError) }
                let request = Paths.getPlaylistItems(
                    playlistID: id,
                    parameters: .init(
                        userID: session.user.id,
                        startIndex: startIndex,
                        limit: pageSize,
                        fields: .MinimumFields,
                        enableUserData: true
                    )
                )
                let response = try await session.client.send(request)
                guard !Task.isCancelled, self.generation == generation else { return }
                let items = response.value.items ?? []
                entries.append(contentsOf: items.enumerated().map {
                    PlaylistEntry(item: $0.element, index: startIndex + $0.offset)
                })
                nextIndex += items.count
                hasNextPage = !items.isEmpty && (response.value.totalRecordCount.map { nextIndex < $0 }
                    ?? PagingPagePolicy.hasNextPage(receivedCount: items.count, pageSize: pageSize))
                isLoading = false
            } catch {
                guard !Task.isCancelled, self.generation == generation else { return }
                self.error = error
                isLoading = false
            }
        }
    }

    deinit { task?.cancel() }
}
