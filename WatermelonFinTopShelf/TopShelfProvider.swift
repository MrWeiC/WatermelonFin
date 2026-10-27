//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import TVServices

private let appGroupInfoPlistKey = "WatermelonFinAppGroupIdentifier"
private let cacheKey = "WatermelonFinTopShelfPayload"

private struct TopShelfPayload: Decodable {
    let version: Int
    let sections: [TopShelfSection]
}

private struct TopShelfSection: Decodable {
    let title: String
    let items: [TopShelfItem]
}

private struct TopShelfItem: Decodable {
    let id: String
    let title: String
    let imageURL: String?
    let displayURL: String
    let playURL: String?
}

final class TopShelfProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent(
        completionHandler: @escaping (TVTopShelfContent?) -> Void
    ) {
        guard let appGroupIdentifier = Bundle.main.object(forInfoDictionaryKey: appGroupInfoPlistKey) as? String,
              let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: cacheKey),
              let payload = try? JSONDecoder().decode(TopShelfPayload.self, from: data),
              payload.version == 2
        else {
            completionHandler(nil)
            return
        }

        let sections = payload.sections.compactMap { section -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? in
            let items = section.items.compactMap(makeTopShelfItem)
            guard !items.isEmpty else { return nil }

            let collection = TVTopShelfItemCollection(items: items)
            collection.title = section.title
            return collection
        }

        completionHandler(sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections))
    }

    private func makeTopShelfItem(_ cacheItem: TopShelfItem) -> TVTopShelfSectionedItem? {
        guard let displayURL = URL(string: cacheItem.displayURL) else { return nil }

        let item = TVTopShelfSectionedItem(identifier: cacheItem.id)
        item.title = cacheItem.title
        item.imageShape = .hdtv
        item.displayAction = TVTopShelfAction(url: displayURL)

        if let playURLString = cacheItem.playURL,
           let playURL = URL(string: playURLString)
        {
            item.playAction = TVTopShelfAction(url: playURL)
        }

        if let imageURLString = cacheItem.imageURL,
           let imageURL = URL(string: imageURLString),
           imageURL.isFileURL
        {
            item.setImageURL(imageURL, for: .screenScale1x)
            item.setImageURL(imageURL, for: .screenScale2x)
        }

        return item
    }
}
