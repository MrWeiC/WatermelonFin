//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct PagingLibraryView<Element: Poster & Identifiable>: View {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    @StateObject
    private var viewModel: PagingLibraryViewModel<Element>
    @Router
    private var router
    init(viewModel: PagingLibraryViewModel<Element>) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 180 : 135), spacing: 16)],
                alignment: .leading,
                spacing: 24
            ) {
                ForEach(viewModel.elements, id: \.unwrappedIDHashOrZero) { item in
                    PosterButton(item: item, type: .portrait, action: { select(item) }) {
                        PosterButton<Element>.TitleSubtitleContentView(item: item)
                    }
                    .onAppear {
                        if item.unwrappedIDHashOrZero == viewModel.elements.last?.unwrappedIDHashOrZero {
                            viewModel.send(.getNextPage)
                        }
                    }
                }
                if viewModel.state == .refreshing || viewModel.backgroundStates.contains(.gettingNextPage) { ProgressView() }
                if case let .error(error) = viewModel.state {
                    VStack {
                        Text(error.localizedDescription)
                        Button(L10n.retry) { viewModel.send(viewModel.elements.isEmpty ? .refresh : .getNextPage) }
                    }
                }
            }.padding(horizontalSizeClass == .regular ? 32 : 16)
        }
        .navigationTitle(viewModel.parent?.displayTitle ?? L10n.library)
        .toolbar {
            if let filter = viewModel.filterViewModel {
                Menu(L10n.filters, systemImage: "line.3.horizontal.decrease.circle") {
                    ForEach(ItemFilterType.allCases, id: \.self) { type in
                        Button(type.displayTitle) { router.route(to: .filter(type: type, viewModel: filter)) }
                    }
                }
            }
        }
        .refreshable { viewModel.send(.refresh) }
        .onFirstAppear { if viewModel.state == .initial { viewModel.send(.refresh) } }
    }

    private func select(_ item: Element) {
        if let item = item as? BaseItemDto {
            if item.type == .folder || item.type == .collectionFolder {
                router.route(to: .library(viewModel: ItemLibraryViewModel(parent: item, filters: .default)))
            } else { router.route(to: .item(item: item)) }
        } else if let person = item as? BaseItemPerson {
            router.route(to: .item(item: BaseItemDto(person: person)))
        }
    }
}
