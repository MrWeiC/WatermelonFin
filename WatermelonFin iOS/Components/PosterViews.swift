//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct PosterButton<Item: Poster>: View {
    let item: Item
    let type: PosterDisplayType
    let action: () -> Void
    private let label: () -> AnyView

    init(item: Item, type: PosterDisplayType, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> any View) {
        self.item = item
        self.type = type
        self.action = action
        self.label = { AnyView(label()) }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                PosterImage(item: item, type: type)
                    .aspectRatio(type == .landscape ? 16.0 / 9.0 : 2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                label().font(.caption).foregroundStyle(.primary).lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayTitle)
        .matchedContextMenu(for: item) { EmptyView() }
    }

    func horizontalAlignment(_ alignment: HorizontalAlignment) -> Self {
        self
    }

    struct TitleContentView: View {
        let item: Item
        var body: some View {
            Text(item.displayTitle)
        }
    }

    struct TitleSubtitleContentView: View {
        let item: Item
        var body: some View {
            VStack(alignment: .leading) {
                Text(item.displayTitle)
                if let subtitle = item.subtitle { Text(subtitle).foregroundStyle(.secondary) }
            }
        }
    }

    struct DefaultOverlay: View {
        let item: Item
        var body: some View {
            EmptyView()
        }
    }
}

struct PosterHStack<Element: Poster, Data: Collection>: View where Data.Element == Element, Data.Index == Int {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    let title: String?
    let type: PosterDisplayType
    let items: Data
    let action: (Element) -> Void
    private let label: (Element) -> AnyView
    private var trailingContent: () -> AnyView = { AnyView(EmptyView()) }

    init(
        title: String? = nil,
        type: PosterDisplayType,
        items: Data,
        action: @escaping (Element) -> Void,
        @ViewBuilder label: @escaping (Element) -> any View = { PosterButton<Element>.TitleSubtitleContentView(item: $0) }
    ) {
        self.title = title
        self.type = type
        self.items = items
        self.action = action
        self.label = { AnyView(label($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let title { Text(title).font(.title3.bold()) }
                Spacer()
                trailingContent()
            }.padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.unwrappedIDHashOrZero) { _, item in
                        PosterButton(item: item, type: type, action: { action(item) }, label: { label(item) })
                            .frame(width: type == .landscape ? (horizontalSizeClass == .regular ? 300 : 230) :
                                (horizontalSizeClass == .regular ? 180 : 140))
                    }
                }.padding(.horizontal)
            }.scrollIndicators(.hidden)
        }.padding(.vertical, 8)
    }

    func trailing(@ViewBuilder _ content: @escaping () -> any View) -> Self {
        var copy = self
        copy.trailingContent = { AnyView(content()) }
        return copy
    }
}
