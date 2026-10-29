//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct SearchView: View {
    @StateObject
    private var viewModel = SearchViewModel()
    @State
    private var query = ""
    @Router
    private var router

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if viewModel.state == .searching { ProgressView() }
                if query.isEmpty {
                    PosterHStack(title: L10n.suggestedSearches, type: .portrait, items: viewModel.suggestions) {
                        router.route(to: .item(item: $0))
                    }
                }
                ForEach(viewModel.items.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { kind in
                    PosterHStack(title: kind.pluralDisplayTitle, type: .portrait, items: viewModel.items[kind] ?? []) {
                        router.route(to: .item(item: $0))
                    }
                }
                if !query.isEmpty && viewModel.state != .searching && viewModel.hasNoResults {
                    ContentUnavailableView.search(text: query)
                }
            }.padding(.vertical)
        }
        .navigationTitle(L10n.search)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.searchMediaLibrary)
        .onChange(of: query) { _, value in viewModel.search(query: value) }
        .onFirstAppear { viewModel.getSuggestions() }
    }
}
