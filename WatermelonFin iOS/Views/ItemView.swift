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
                        if let series = viewModel as? SeriesItemViewModel { MobileEpisodeSelector(viewModel: series) }
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

private struct MobileEpisodeSelector: View {
    @ObservedObject
    var viewModel: SeriesItemViewModel
    @State
    private var selection: SeasonItemViewModel.ID?

    private var selectedSeason: SeasonItemViewModel? {
        viewModel.seasons.first { $0.id == selection } ?? viewModel.seasons.first
    }

    var body: some View {
        if let selectedSeason {
            // Season rows render nothing until loaded, so load from a view that is always on screen.
            MobileSeasonEpisodes(viewModel: selectedSeason) { seasonPicker(selected: selectedSeason) }
                .id(selectedSeason.id)
                .task(id: selectedSeason.id) {
                    if selectedSeason.state == .initial { selectedSeason.send(.refresh) }
                }
                .onChange(of: viewModel.playButtonItem?.seasonID, initial: true) { _, seasonID in
                    // Open on the next-up season until the viewer picks one.
                    if selection == nil, let seasonID, viewModel.seasons.contains(where: { $0.id == seasonID }) { selection = seasonID }
                }
        }
    }

    @ViewBuilder
    private func seasonPicker(selected: SeasonItemViewModel) -> some View {
        if viewModel.seasons.count > 1 {
            Menu {
                Picker(L10n.season, selection: Binding { selected.id } set: { selection = $0 }) {
                    ForEach(viewModel.seasons) { season in
                        Text(season.season.displayTitle).tag(season.id)
                    }
                }
            } label: {
                Label(selected.season.displayTitle, systemImage: "chevron.up.chevron.down")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityIdentifier("mobile.item.seasonPicker")
        } else {
            Text(selected.season.displayTitle).foregroundStyle(.secondary)
        }
    }
}

private struct MobileSeasonEpisodes<Trailing: View>: View {
    @ObservedObject
    var viewModel: SeasonItemViewModel
    @ViewBuilder
    let picker: () -> Trailing
    @Router
    private var router

    var body: some View {
        if viewModel.elements.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.episodes).font(.title3.bold())
                    Spacer()
                    picker()
                }
                switch viewModel.state {
                case .initial, .refreshing:
                    ProgressView()
                case let .error(error):
                    Text(error.localizedDescription).foregroundStyle(.secondary)
                    Button(L10n.retry) { viewModel.send(.refresh) }
                case .content:
                    Text(L10n.noEpisodesAvailable).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        } else {
            PosterHStack(title: L10n.episodes, type: .landscape, items: viewModel.elements) {
                router.route(to: .item(item: $0))
            }.trailing {
                picker()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mobile.item.episodes")
        }
    }
}
