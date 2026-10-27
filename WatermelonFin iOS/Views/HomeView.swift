//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

struct HomeView: View {
    @StateObject
    private var viewModel = HomeViewModel()
    @Router
    private var router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if case let .error(error) = viewModel.state {
                    Text(error.localizedDescription).foregroundStyle(.secondary).padding()
                    Button(L10n.retry) { viewModel.send(.refresh) }
                }
                if viewModel.state == .refreshing { ProgressView().padding() }
                PosterHStack(title: L10n.resume, type: .landscape, items: viewModel.resumeItems.elements) {
                    router.route(to: .item(item: $0))
                }
                MobileLibraryRow(title: L10n.nextUp, viewModel: viewModel.nextUpViewModel)
                MobileLibraryRow(title: L10n.recentlyAdded, viewModel: viewModel.recentlyAddedViewModel)
                ForEach(viewModel.libraries) { library in
                    MobileLibraryRow(title: library.parent?.displayTitle ?? L10n.library, viewModel: library)
                }
            }.padding(.vertical)
        }
        .navigationTitle(L10n.home)
        .refreshable { viewModel.send(.refresh) }
        .onFirstAppear { viewModel.send(.refresh) }
        .onReceive(Notifications[.didRequestGlobalRefresh].publisher) { _ in viewModel.send(.backgroundRefresh) }
    }
}

struct MobileLibraryRow: View {
    let title: String
    @ObservedObject
    var viewModel: PagingLibraryViewModel<BaseItemDto>
    @Router
    private var router

    var body: some View {
        if !viewModel.elements.isEmpty {
            PosterHStack(title: title, type: .portrait, items: viewModel.elements) {
                router.route(to: .item(item: $0))
            }.trailing {
                Button(L10n.seeAll) { router.route(to: .library(viewModel: viewModel)) }
            }
        }
    }
}
