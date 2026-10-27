//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(tvOS)
import Factory
import Foundation
import JellyfinAPI
import TVServices

@MainActor
enum TopShelfCache {

    static let payloadKey = "WatermelonFinTopShelfPayload"
    nonisolated static let maxItemsPerSection = 12

    private static let appGroupInfoPlistKey = "WatermelonFinAppGroupIdentifier"
    private static let defaultAppGroupIdentifier = "group.org.chenacademy.watermelonfin"
    private static let payloadVersion = 2
    private static var artworkTask: Task<Void, Never>?
    private static var updateID = UUID()

    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: appGroupInfoPlistKey) as? String ?? defaultAppGroupIdentifier
    }

    static func update(
        resumeItems: [BaseItemDto],
        nextUpItems: [BaseItemDto],
        session: UserSession
    ) {
        // A delayed home refresh from a signed-out account must not republish its library.
        guard Container.shared.currentUserSession() === session else { return }
        clear()
        var payload = makePayload(resumeItems: resumeItems, nextUpItems: nextUpItems, session: session)
        guard payload.sections.isNotEmpty else { return }
        // Publish token-free metadata immediately, even if artwork cannot be fetched.
        persist(payload)

        guard let directory = artworkDirectory else { return }
        let generation = updateID
        let downloadDirectory = directory.appendingPathComponent(generation.uuidString, isDirectory: true)
        let artworkURLs = Dictionary(
            (resumeItems + nextUpItems).compactMap { item -> (String, URL)? in
                guard let id = item.id, let url = imageURL(for: item, session: session) else { return nil }
                return (id, url)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let accessToken = session.user.accessToken
        artworkTask = Task {
            let downloader = URLSession(configuration: .ephemeral)
            defer { downloader.invalidateAndCancel() }
            for sectionIndex in payload.sections.indices {
                for itemIndex in payload.sections[sectionIndex].items.indices {
                    guard !Task.isCancelled, generation == updateID else { return }
                    let id = payload.sections[sectionIndex].items[itemIndex].id
                    guard let remoteURL = artworkURLs[id] else { continue }
                    do {
                        var request = URLRequest(url: remoteURL)
                        request.setValue(accessToken, forHTTPHeaderField: "X-Emby-Token")
                        request.timeoutInterval = 15
                        let (data, response) = try await downloader.data(for: request)
                        guard !Task.isCancelled, generation == updateID else { return }
                        guard let response = response as? HTTPURLResponse,
                              (200 ..< 300).contains(response.statusCode),
                              response.mimeType?.hasPrefix("image/") == true
                        else { continue }
                        let localURL = try TopShelfArtworkStore.write(data, to: downloadDirectory)
                        payload.sections[sectionIndex].items[itemIndex].imageURL = localURL.absoluteString
                    } catch {
                        // Artwork is optional; never fall back to a persisted authenticated URL.
                        continue
                    }
                }
            }
            guard !Task.isCancelled, generation == updateID else { return }
            persist(payload)
        }
    }

    static func clear() {
        updateID = UUID()
        artworkTask?.cancel()
        artworkTask = nil
        sharedDefaults?.removeObject(forKey: payloadKey)
        if let artworkDirectory {
            try? FileManager.default.removeItem(at: artworkDirectory)
        }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    private static var artworkDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Library/Caches/TopShelfArtwork", isDirectory: true)
    }

    private static func persist(_ payload: TopShelfPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        sharedDefaults?.set(data, forKey: payloadKey)
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    static func item(id: String, session: UserSession) async throws -> BaseItemDto {
        let request = Paths.getItem(itemID: id, userID: session.user.id)
        let response = try await session.client.send(request)
        return response.value
    }

    static func makePayload(
        resumeItems: [BaseItemDto],
        nextUpItems: [BaseItemDto],
        session: UserSession
    ) -> TopShelfPayload {
        let sections = [
            makeSection(
                title: L10n.resume,
                items: resumeItems,
                session: session
            ),
            makeSection(
                title: L10n.nextUp,
                items: nextUpItems,
                session: session
            ),
        ]
            .compactMap { $0 }

        return TopShelfPayload(
            version: payloadVersion,
            updatedAt: Date.now.timeIntervalSince1970,
            sections: sections
        )
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private static func makeSection(
        title: String,
        items: [BaseItemDto],
        session: UserSession
    ) -> TopShelfSection? {
        let topShelfItems = items
            .prefix(maxItemsPerSection)
            .compactMap { makeItem($0, session: session) }

        guard topShelfItems.isNotEmpty else { return nil }

        return TopShelfSection(
            title: title,
            items: topShelfItems
        )
    }

    private static func makeItem(
        _ item: BaseItemDto,
        session: UserSession
    ) -> TopShelfItem? {
        guard let id = item.id,
              let displayURL = TopShelfDeepLink(action: .item, itemID: id).url
        else { return nil }

        let playURL: URL? = {
            guard item.isPlayable else { return nil }
            return TopShelfDeepLink(action: .play, itemID: id).url
        }()

        return TopShelfItem(
            id: id,
            title: title(for: item),
            imageURL: nil,
            displayURL: displayURL.absoluteString,
            playURL: playURL?.absoluteString
        )
    }

    private static func title(for item: BaseItemDto) -> String {
        if item.type == .episode,
           let seriesName = item.seriesName,
           seriesName.isNotEmpty
        {
            return seriesName
        }

        return item.displayTitle
    }

    private static func imageURL(
        for item: BaseItemDto,
        session: UserSession
    ) -> URL? {
        let candidates: [URL?]

        if item.type == .episode {
            candidates = [
                item.imageURL(.thumb, maxWidth: 1920, quality: 90),
                item.imageURL(.backdrop, maxWidth: 1920, quality: 90),
                item.seriesImageURL(.backdrop, maxWidth: 1920, quality: 90),
                item.imageURL(.primary, maxWidth: 600, quality: 90),
            ]
        } else {
            candidates = [
                item.imageURL(.thumb, maxWidth: 1920, quality: 90),
                item.imageURL(.backdrop, maxWidth: 1920, quality: 90),
                item.imageURL(.primary, maxWidth: 600, quality: 90),
            ]
        }

        return candidates
            .compactMap { $0 }
            .first
    }
}

struct TopShelfPayload: Codable, Equatable {
    let version: Int
    let updatedAt: TimeInterval
    var sections: [TopShelfSection]
}

struct TopShelfSection: Codable, Equatable {
    let title: String
    var items: [TopShelfItem]
}

struct TopShelfItem: Codable, Equatable {
    let id: String
    let title: String
    var imageURL: String?
    let displayURL: String
    let playURL: String?
}

struct TopShelfDeepLink: Equatable {

    enum Action: String {
        case item
        case play
    }

    let action: Action
    let itemID: String

    init(action: Action, itemID: String) {
        self.action = action
        self.itemID = itemID
    }

    init?(url: URL) {
        guard url.scheme == "watermelonfin",
              url.host == "topshelf",
              let action = Action(rawValue: url.lastPathComponent),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let itemID = components.queryItems?.first(where: { $0.name == "id" })?.value,
              itemID.isNotEmpty
        else { return nil }

        self.action = action
        self.itemID = itemID
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = "watermelonfin"
        components.host = "topshelf"
        components.path = "/\(action.rawValue)"
        components.queryItems = [
            URLQueryItem(name: "id", value: itemID),
        ]
        return components.url
    }
}

@MainActor
enum TopShelfDeepLinkStore {

    private static var pendingURL: URL?

    static func receive(_ url: URL) {
        guard TopShelfDeepLink(url: url) != nil else { return }

        pendingURL = url
        Notifications[.didReceiveDeepLink].post(url)
    }

    static func consumePendingURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }

    static func markHandled(_ url: URL) {
        guard pendingURL == url else { return }
        pendingURL = nil
    }
}

#endif
