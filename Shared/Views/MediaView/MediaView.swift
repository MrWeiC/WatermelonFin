//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Engine
import JellyfinAPI
import SwiftUI

struct MediaView: View {

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    @Router
    private var router

    @StateObject
    private var viewModel = MediaViewModel()

    @Default(.Customization.Library.hiddenLibraryIDs)
    private var hiddenLibraryIDs
    @Default(.Customization.Library.showFavorites)
    private var showFavorites

    private let hidesNavigationBarOnTV: Bool

    init(
        hidesNavigationBarOnTV: Bool = true,
        viewModel: MediaViewModel? = nil
    ) {
        self.hidesNavigationBarOnTV = hidesNavigationBarOnTV
        _viewModel = StateObject(wrappedValue: viewModel ?? MediaViewModel())
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize, !UIDevice.isTV {
            [GridItem(.flexible())]
        } else if UIDevice.isTV {
            Array(
                repeating: GridItem(.flexible(), spacing: 50),
                count: 4
            )
        } else if UIDevice.isPad {
            [GridItem(.adaptive(minimum: 200), spacing: 20)]
        } else {
            Array(
                repeating: GridItem(.flexible(), spacing: 12),
                count: 2
            )
        }
    }

    private var contentInsets: CGFloat {
        if UIDevice.isTV {
            50
        } else if UIDevice.isPad {
            20
        } else {
            16
        }
    }

    @ViewBuilder
    private func section(_ section: MediaViewModel.MediaType.Section) -> some View {
        let mediaItems = viewModel.mediaItems(in: section)

        if mediaItems.isNotEmpty {
            VStack(alignment: .leading, spacing: UIDevice.isTV ? 24 : 12) {
                Text(section.displayTitle)
                    .font(UIDevice.isTV ? .title : .title2)
                    .fontWeight(.bold)

                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: UIDevice.isTV ? 50 : 20
                ) {
                    ForEach(mediaItems) { mediaType in
                        MediaItem(viewModel: viewModel, type: mediaType) { namespace in
                            route(mediaType, in: namespace)
                        }
                    }
                }
                .platformFocusSection()
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: UIDevice.isTV ? 56 : 32) {
                section(.libraries)
                section(.collections)
                section(.favorites)
            }
            .padding(.horizontal, contentInsets)
            .padding(.top, UIDevice.isTV ? 48 : 16)
            .padding(.bottom, UIDevice.isTV ? 80 : 32)
        }
        .scrollIndicators(.hidden)
    }

    private func route(_ mediaType: MediaViewModel.MediaType, in namespace: Namespace.ID) {
        switch mediaType {
        case let .collectionLibrary(item), let .library(item):
            let viewModel = ItemLibraryViewModel(
                parent: item,
                filters: mediaType.libraryFilters
            )
            router.route(to: .library(viewModel: viewModel), in: namespace)
        case .favorites:
            let viewModel = ItemLibraryViewModel(
                title: L10n.favorites,
                id: "favorites",
                filters: .favorites
            )
            router.route(to: .library(viewModel: viewModel), in: namespace)
        case .liveTV:
            router.route(to: .liveTV)
        }
    }

    private var viewState: StateContainer<AnyView, EmptyStateView>.ViewState {
        switch viewModel.state {
        case .initial:
            if !viewModel.hasLoaded {
                return .loading
            }
            return viewModel.mediaItems.isEmpty ? .empty : .content
        case .error:
            return .error(viewModel.error ?? ErrorMessage(L10n.unknownError))
        case .refreshing:
            return .loading
        }
    }

    var body: some View {
        StateContainer(
            state: viewState,
            emptyMessage: L10n.noLibrariesFound,
            emptySystemImage: "rectangle.stack.badge.minus"
        ) {
            content
                .eraseToAnyView()
        }
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .if(UIDevice.isTV) { $0.ignoresSafeArea() }
        .navigationTitle(L10n.allMedia.localizedCapitalized)
        .refreshable {
            viewModel.invalidateCardDataCache()
            viewModel.refresh()
        }
        .onFirstAppear {
            if !viewModel.hasLoaded {
                viewModel.refresh()
            }
        }
        .onChange(of: hiddenLibraryIDs) {
            viewModel.refresh()
        }
        .onChange(of: showFavorites) {
            viewModel.refresh()
        }
        .onReceive(Notifications[.itemShouldRefreshMetadata].publisher) { _ in
            viewModel.invalidateCardDataCache()
        }
        .if(UIDevice.isTV) { view in
            if hidesNavigationBarOnTV {
                view.toolbar(.hidden, for: .navigationBar)
            } else {
                view
            }
        }
    }
}
