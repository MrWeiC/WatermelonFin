//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import JellyfinAPI
import OrderedCollections
import SwiftUI

extension ItemView {

    struct CollectionItemContentView: View {

        typealias Element = OrderedDictionary<BaseItemKind, ItemLibraryViewModel>.Elements.Element

        @Router
        private var router

        @ObservedObject
        var viewModel: CollectionItemViewModel

        @State
        private var error: Error?

        // MARK: - Episode Poster HStack

        private func episodeHStack(element: Element) -> some View {
            VStack(alignment: .leading, spacing: 20) {

                HStack {
                    Text(L10n.episodes)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibility(addTraits: [.isHeader])
                        .padding(.leading, 50)

                    Spacer()
                    Button(L10n.seeAll) {
                        router.route(to: .library(viewModel: element.value))
                    }
                    .padding(.trailing, 50)
                }

                CollectionHStack(
                    uniqueElements: element.value.elements,
                    id: \.unwrappedIDHashOrZero,
                    columns: 3.5
                ) { episode in
                    SeriesEpisodeSelector.EpisodeCard(episode: episode)
                        .padding(.horizontal, 4)
                }
                .scrollBehavior(.continuousLeadingEdge)
                .insets(horizontal: EdgeInsets.edgePadding)
                .itemSpacing(EdgeInsets.edgePadding / 2)
            }
            .platformFocusSection()
        }

        // MARK: - Default Poster HStack

        private func posterHStack(element: Element) -> some View {
            PosterHStack(
                title: element.key.pluralDisplayTitle,
                type: .portrait,
                items: element.value.elements
            ) { item in
                router.route(to: .item(item: item))
            }
            .trailing {
                Button(L10n.seeAll) {
                    router.route(to: .library(viewModel: element.value))
                }
            }
            .platformFocusSection()
        }

        var body: some View {
            VStack(spacing: 0) {
                if let entries = viewModel.playlistEntries {
                    PlaylistEntriesView(viewModel: entries, collection: viewModel)
                }

                ForEach(
                    viewModel.sections.elements,
                    id: \.key
                ) { element in
                    if element.key == .episode {
                        episodeHStack(element: element)
                    } else {
                        posterHStack(element: element)
                    }
                }

                if viewModel.similarItems.isNotEmpty {
                    ItemView.SimilarItemsHStack(items: viewModel.similarItems)
                }

                ItemView.AboutView(viewModel: viewModel)
            }
            .contextMenu(for: BaseItemDto.self) { item in
                if viewModel.item.type == .playlist, item.playlistItemID != nil {
                    Button(PlaylistL10n.removeFromPlaylist, systemImage: "trash", role: .destructive) {
                        removeFromPlaylist(item)
                    }
                }
            }
            .errorMessage($error)
        }

        private func removeFromPlaylist(_ item: BaseItemDto) {
            Task {
                do {
                    try await viewModel.removeFromPlaylist(item)
                } catch {
                    self.error = error
                }
            }
        }
    }
}
