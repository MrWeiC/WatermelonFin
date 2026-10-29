//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct ItemView: View {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @StateObject
    private var viewModel: ItemViewModel
    @Router
    private var router
    @State
    private var showPlaylistPicker = false

    init(item: BaseItemDto) {
        let model: ItemViewModel
        switch item.type {
        case .series: model = SeriesItemViewModel(item: item)
        case .movie: model = MovieItemViewModel(item: item)
        case .episode: model = EpisodeItemViewModel(item: item)
        case .boxSet, .playlist, .person, .musicArtist, .musicAlbum, .season:
            model = CollectionItemViewModel(item: item)
        default: model = ItemViewModel(item: item)
        }
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                // Keep the summary mounted when a full-screen player rotates and dismisses.
                VStack(alignment: .leading, spacing: 20) {
                    if geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 32) {
                            artwork.frame(maxWidth: 420)
                            itemSummary.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        artwork
                        itemSummary
                    }
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let people = viewModel.item.people, !people.isEmpty {
                            CastAndCrewHStack(people: people)
                        }
                        if let overview = viewModel.item.overview { Text(overview).textSelection(.enabled) }
                        if let collection = viewModel as? CollectionItemViewModel {
                            MobileCollectionRows(viewModel: collection)
                        }
                        if let series = viewModel as? SeriesItemViewModel { MobileSeasonRows(viewModel: series) }
                        if !viewModel.specialFeatures.isEmpty {
                            PosterHStack(title: L10n.specialFeatures, type: .landscape, items: viewModel.specialFeatures) {
                                router.route(to: .item(item: $0))
                            }
                        }
                        if !viewModel.similarItems.isEmpty {
                            PosterHStack(title: L10n.recommended, type: .portrait, items: viewModel.similarItems) {
                                router.route(to: .item(item: $0))
                            }
                        }
                    }
                }
                .padding(horizontalSizeClass == .regular ? 32 : 16)
                .frame(maxWidth: 1200, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onFirstAppear { viewModel.send(.refresh) }
        .refreshable { viewModel.send(.refresh) }
        .sheet(isPresented: $showPlaylistPicker) {
            if let id = viewModel.item.id { PlaylistPickerView(itemID: id) }
        }
    }

    private var artwork: some View {
        PosterImage(item: viewModel.item, type: .landscape)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }

    private var itemSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.item.displayTitle).font(.largeTitle.bold()).textSelection(.enabled)
            if let subtitle = viewModel.item.subtitle { Text(subtitle).foregroundStyle(.secondary) }
            if viewModel.state == .refreshing { ProgressView() }
            if case let .error(error) = viewModel.state {
                Text(error.localizedDescription)
                Button(L10n.retry) { viewModel.send(.refresh) }
            }
            if let item = viewModel.playButtonItem {
                Button {
                    play(item: item)
                } label: {
                    Label(item.playButtonLabel, systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("mobile.item.play")
                .accessibilityLabel((item.userData?.playbackPositionTicks ?? 0) > 0 ? L10n.resume : L10n.play)
                .accessibilityValue(item.playButtonLabel)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if let sources = item.mediaSources, sources.count > 1 {
                    Menu(L10n.version) {
                        ForEach(sources, id: \.id) { source in
                            Button(source.displayTitle) { viewModel.send(.selectMediaSource(source)) }
                        }
                    }
                }
                if (item.userData?.playbackPositionTicks ?? 0) > 0 {
                    Button(L10n.playFromBeginning, systemImage: "gobackward") { play(item: item, fromBeginning: true) }
                }
            }
            ScrollView(.horizontal) {
                ActionButtonHStack(viewModel: viewModel)
            }.scrollIndicators(.hidden)
        }
    }

    private func play(item: BaseItemDto, fromBeginning: Bool = false) {
        let queue: (any MediaPlayerQueue)? = item.type == .episode ? EpisodeMediaPlayerQueue(episode: item) : nil
        let source = viewModel.selectedMediaSource
        let provider = MediaPlayerItemProvider(item: item) { item in
            try await MediaPlayerItem.build(for: item, mediaSource: source) {
                if fromBeginning { $0.userData?.playbackPositionTicks = 0 }
            }
        }
        router.route(to: .videoPlayer(provider: provider, queue: queue))
    }
}

private struct MobileCollectionRows: View {
    @ObservedObject
    var viewModel: CollectionItemViewModel
    var body: some View {
        if let entries = viewModel.playlistEntries {
            PlaylistEntriesView(viewModel: entries, collection: viewModel)
        } else {
            ForEach(viewModel.sections.elements, id: \.key) { section in
                MobileLibraryRow(title: section.key.pluralDisplayTitle, viewModel: section.value)
            }
        }
    }
}

private struct MobileSeasonRows: View {
    @ObservedObject
    var viewModel: SeriesItemViewModel
    var body: some View {
        ForEach(viewModel.seasons) { season in
            MobileLibraryRow(title: season.season.displayTitle, viewModel: season)
                .onAppear { if season.state == .initial { season.send(.refresh) } }
        }
    }
}
