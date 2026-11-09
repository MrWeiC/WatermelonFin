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

/// Season picker plus the selected season's episodes.
///
/// Episodes are loaded per season on demand. The loading trigger lives on a view that is always
/// rendered (even while the season has no episodes yet), so the first load can't be skipped.
private struct MobileSeasonRows: View {
    @ObservedObject
    var viewModel: SeriesItemViewModel
    @State
    private var selection: SeasonItemViewModel.ID?

    private var selectedSeason: SeasonItemViewModel? {
        viewModel.seasons.first(where: { $0.id == selection }) ?? viewModel.seasons.first
    }

    var body: some View {
        if !viewModel.seasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.seasons).font(.title3.bold()).padding(.horizontal)
                seasonPicker
                // Seasons are rebuilt on every series refresh; start fresh for each new model.
                if let selectedSeason {
                    MobileSeasonEpisodes(viewModel: selectedSeason).id(ObjectIdentifier(selectedSeason))
                }
            }
            .padding(.vertical, 8)
            .onChange(of: viewModel.playButtonItem?.seasonID) { _, seasonID in selectPlayButtonSeason(seasonID) }
            .onAppear { selectPlayButtonSeason(viewModel.playButtonItem?.seasonID) }
        }
    }

    private var seasonPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(viewModel.seasons) { season in
                        let isSelected = season.id == selectedSeason?.id
                        Button {
                            selection = season.id
                        } label: {
                            Text(season.season.displayTitle).lineLimit(1)
                        }
                        .buttonStyle(SeasonChipStyle(isSelected: isSelected))
                        .accessibilityIdentifier("mobile.series.season")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(season.id)
                    }
                }.padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, newValue in
                guard let newValue else { return }
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    /// Start on the season holding the next-up/resume episode, until the user picks one.
    private func selectPlayButtonSeason(_ seasonID: String?) {
        guard selection == nil, let seasonID, viewModel.seasons.contains(where: { $0.id == seasonID }) else { return }
        selection = seasonID
    }
}

private struct SeasonChipStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

private struct MobileSeasonEpisodes: View {
    @ObservedObject
    var viewModel: SeasonItemViewModel
    @Router
    private var router

    var body: some View {
        Group {
            if !viewModel.elements.isEmpty {
                PosterHStack(type: .landscape, items: viewModel.elements) {
                    router.route(to: .item(item: $0))
                } label: { episode in
                    VStack(alignment: .leading) {
                        if let locator = episode.episodeLocator { Text(locator).foregroundStyle(.secondary) }
                        Text(episode.displayTitle)
                    }
                }
            } else if case let .error(error) = viewModel.state {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription).foregroundStyle(.secondary)
                    Button(L10n.retry) { viewModel.send(.refresh) }
                }.padding(.horizontal)
            } else if viewModel.state == .content {
                Text(L10n.noEpisodesAvailable).foregroundStyle(.secondary).padding(.horizontal)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .onAppear { if viewModel.state == .initial { viewModel.send(.refresh) } }
    }
}
