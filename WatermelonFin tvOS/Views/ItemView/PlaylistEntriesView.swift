//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// A lazy, ordered list avoids both the horizontal-row cap and media-ID deduplication.
struct PlaylistEntriesView: View {
    @ObservedObject
    var viewModel: PlaylistEntriesViewModel
    @ObservedObject
    var collection: CollectionItemViewModel
    @Router
    private var router
    @State
    private var removalError: Error?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    router.route(to: .item(item: entry.item))
                } label: {
                    HStack(spacing: 24) {
                        Text("\(index + 1)").monospacedDigit()
                        Text(entry.item.displayTitle)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                }
                .contextMenu {
                    if entry.item.playlistItemID != nil {
                        Button(PlaylistL10n.removeFromPlaylist, systemImage: "trash", role: .destructive) {
                            Task {
                                do { try await collection.removeFromPlaylist(entry.item) }
                                catch { removalError = error }
                            }
                        }
                    }
                }
                .onAppear {
                    if index >= viewModel.entries.count - 5 { viewModel.loadNextPage() }
                }
            }
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.error {
                Text(error.localizedDescription)
                Button(L10n.retry) { viewModel.loadNextPage() }
            } else if viewModel.hasNextPage {
                Button(L10n.seeAll) { viewModel.loadNextPage() }
            }
        }
        .padding(.horizontal, EdgeInsets.edgePadding)
        .errorMessage($removalError)
    }
}
