//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct ActionButtonHStack: View {

        @StoredValue(.User.enabledTrailers)
        private var enabledTrailers: TrailerSelection

        // MARK: - Observed, State, & Environment Objects

        @Router
        private var router

        @ObservedObject
        var viewModel: ItemViewModel

        @StateObject
        private var deleteViewModel: DeleteItemViewModel
        @StateObject
        private var metadataViewModel: RefreshMetadataViewModel

        // MARK: - Dialog States

        @State
        private var showConfirmationDialog = false
        @State
        private var isPresentingEventAlert = false
        @State
        private var isPresentingPlaylistPicker = false

        // MARK: - Error State

        @State
        private var error: Error?

        // MARK: - Can Delete Item

        private var canDelete: Bool {
            viewModel.userSession?.user.permissions.items.canDelete(item: viewModel.item) == true
        }

        // MARK: - Can Refresh Item

        private var canRefresh: Bool {
            viewModel.userSession?.user.permissions.items.canEditMetadata(item: viewModel.item) == true
        }

        // MARK: - Can Manage Subtitles

        private var canManageSubtitles: Bool {
            viewModel.userSession?.user.permissions.items.canManageSubtitles(item: viewModel.item) == true
        }

        // MARK: - Deletion or Refreshing is Enabled

        private var enableMenu: Bool {
            canDelete || canRefresh
        }

        // MARK: - Has Trailers

        private var hasTrailers: Bool {
            if enabledTrailers.contains(.local), viewModel.localTrailers.isNotEmpty {
                return true
            }

            if enabledTrailers.contains(.external), viewModel.item.remoteTrailers?.isNotEmpty == true {
                return true
            }

            return false
        }

        // MARK: - Can Add to a Video Playlist

        private var canAddToPlaylist: Bool {
            guard viewModel.item.id != nil else { return false }

            switch viewModel.item.type {
            case .episode, .movie, .musicVideo, .trailer, .video:
                return true
            default:
                return false
            }
        }

        // MARK: - Initializer

        init(viewModel: ItemViewModel) {
            self.viewModel = viewModel
            self._deleteViewModel = StateObject(wrappedValue: .init(item: viewModel.item))
            self._metadataViewModel = StateObject(wrappedValue: .init(item: viewModel.item))
        }

        // MARK: - Body

        var body: some View {
            HStack(alignment: .center, spacing: 30) {

                // MARK: Toggle Played

                if viewModel.item.canBePlayed {
                    let isPlayed: Bool = viewModel.item.userData?.isPlayed == true

                    Button(
                        isPlayed ? L10n.markUnwatched : L10n.markWatched,
                        systemImage: isPlayed ? "circle" : "checkmark.circle"
                    ) {
                        viewModel.send(.toggleIsPlayed)
                    }
                    .buttonStyle(.tintedMaterial(tint: Color.watermelonGreen, foregroundColor: .primary))
                    .isSelected(isPlayed)
                    .frame(width: UIDevice.isTV ? 100 : 48, height: UIDevice.isTV ? 100 : 48)
                }

                // MARK: Toggle Favorite

                let isHeartSelected: Bool = viewModel.item.userData?.isFavorite == true

                Button(
                    isHeartSelected ? L10n.favorited : L10n.favorite,
                    systemImage: isHeartSelected ? "heart.fill" : "heart"
                ) {
                    viewModel.send(.toggleIsFavorite)
                }
                .buttonStyle(.tintedMaterial(tint: .pink, foregroundColor: .primary))
                .isSelected(isHeartSelected)
                .frame(width: UIDevice.isTV ? 100 : 48, height: UIDevice.isTV ? 100 : 48)

                // MARK: Add to Playlist

                if canAddToPlaylist {
                    Button(PlaylistL10n.addToPlaylist, systemImage: "rectangle.stack.badge.plus") {
                        isPresentingPlaylistPicker = true
                    }
                    .buttonStyle(.tintedMaterial(tint: Color.watermelonRed, foregroundColor: .primary))
                    .frame(width: UIDevice.isTV ? 100 : 48, height: UIDevice.isTV ? 100 : 48)
                }

                // MARK: Watch a Trailer

                if hasTrailers {
                    TrailerMenu(
                        localTrailers: viewModel.localTrailers,
                        externalTrailers: viewModel.item.remoteTrailers ?? []
                    )
                    .buttonStyle(.tintedMaterial(tint: .pink, foregroundColor: .primary))
                    .frame(width: UIDevice.isTV ? 100 : 48, height: UIDevice.isTV ? 100 : 48)
                }

                // MARK: Advanced Options

                if enableMenu {
                    Menu {
                        if canRefresh || canManageSubtitles {
                            Section(L10n.manage) {
                                if canRefresh {
                                    Button(L10n.refreshMetadata, systemImage: "arrow.clockwise") {
                                        router.route(to: .itemMetadataRefresh(viewModel: metadataViewModel))
                                    }
                                }

                                if canManageSubtitles {
                                    Button(L10n.subtitles, systemImage: "textformat") {
                                        router.route(
                                            to: .searchSubtitle(
                                                viewModel: .init(item: viewModel.item)
                                            )
                                        )
                                    }
                                }
                            }
                        }

                        if canDelete {
                            Section {
                                Button(L10n.delete, systemImage: "trash", role: .destructive) {
                                    showConfirmationDialog = true
                                }
                            }
                        }
                    } label: {
                        Label(L10n.advanced, systemImage: "ellipsis")
                            .rotationEffect(.degrees(90))
                    }
                    .buttonStyle(.material)
                    .frame(width: 60, height: 100)
                }
            }
            .frame(height: 100)
            .labelStyle(.iconOnly)
            .font(.title3)
            .fontWeight(.semibold)
            .confirmationDialog(
                L10n.deleteItemConfirmationMessage,
                isPresented: $showConfirmationDialog,
                titleVisibility: .visible
            ) {
                Button(L10n.confirm, role: .destructive) {
                    deleteViewModel.send(.delete)
                }
                Button(L10n.cancel, role: .cancel) {}
            }
            .onReceive(deleteViewModel.events) { event in
                switch event {
                case let .error(eventError):
                    error = eventError
                case .deleted:
                    router.dismiss()
                }
            }
            .sheet(isPresented: $isPresentingPlaylistPicker) {
                if let itemID = viewModel.item.id {
                    PlaylistPickerView(itemID: itemID)
                }
            }
            .errorMessage($error)
        }
    }
}
