//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

extension MediaViewModel {

    enum MediaType: Displayable, Hashable, Identifiable {

        case collectionLibrary(BaseItemDto)
        case favorites
        case library(BaseItemDto)
        case liveTV(BaseItemDto)

        enum Section: CaseIterable, Identifiable {
            case libraries
            case collections
            case favorites

            var id: Self {
                self
            }

            var displayTitle: String {
                switch self {
                case .libraries:
                    L10n.libraries
                case .collections:
                    L10n.collections
                case .favorites:
                    L10n.favorites
                }
            }
        }

        static func makeMediaItems(
            from userViews: [BaseItemDto],
            hiddenLibraryIDs: Set<String>,
            showFavorites: Bool
        ) -> [MediaType] {
            let libraries = userViews.compactMap { userView -> MediaType? in
                guard let id = userView.id,
                      !hiddenLibraryIDs.contains(id)
                else {
                    return nil
                }

                return MediaType(userView: userView)
            }

            return libraries.prepending(.favorites, if: showFavorites)
        }

        init?(userView: BaseItemDto) {
            guard let collectionType = userView.collectionType,
                  CollectionType.supportedCases.contains(collectionType)
            else {
                return nil
            }

            switch collectionType {
            case .boxsets:
                self = .collectionLibrary(userView)
            case .livetv:
                return nil
            default:
                self = .library(userView)
            }
        }

        var section: Section {
            switch self {
            case .collectionLibrary:
                .collections
            case .favorites:
                .favorites
            case .library, .liveTV:
                .libraries
            }
        }

        var libraryItem: BaseItemDto? {
            switch self {
            case let .collectionLibrary(item), let .library(item), let .liveTV(item):
                item
            case .favorites:
                nil
            }
        }

        var displayTitle: String {
            switch self {
            case let .collectionLibrary(item), let .library(item):
                return item.localizedCollectionDisplayTitle
            case .favorites:
                return L10n.favorites
            case .liveTV:
                return L10n.liveTV
            }
        }

        var id: String {
            switch self {
            case let .collectionLibrary(item), let .library(item), let .liveTV(item):
                return item.id ?? "library-\(displayTitle)"
            case .favorites:
                return "favorites"
            }
        }

        var systemImage: String {
            switch self {
            case .collectionLibrary:
                "rectangle.stack.fill"
            case .favorites:
                "heart.fill"
            case let .library(item):
                switch item.collectionType {
                case .folders:
                    "folder.fill"
                case .homevideos:
                    "video.fill"
                case .movies:
                    "film.fill"
                case .music:
                    "music.note"
                case .musicvideos:
                    "music.note"
                case .playlists:
                    "list.bullet"
                case .trailers:
                    "play.rectangle.fill"
                case .tvshows:
                    "tv.fill"
                default:
                    "rectangle.stack.fill"
                }
            case .liveTV:
                "antenna.radiowaves.left.and.right"
            }
        }

        var previewItemTypes: [BaseItemKind] {
            switch self {
            case let .collectionLibrary(item), let .library(item):
                item.supportedItemTypes
            case .favorites:
                BaseItemKind.supportedCases
            case .liveTV:
                []
            }
        }

        var libraryFilters: ItemFilterCollection {
            switch self {
            case .collectionLibrary:
                // Jellyfin can replace a BoxSet-only child query with the
                // server's root views. Including UserView keeps the parent
                // query intact; the parent itself is filtered separately.
                .init(itemTypes: [.boxSet, .userView])
            default:
                .default
            }
        }

        func countLabel(_ count: Int) -> String {
            switch self {
            case .collectionLibrary:
                BaseItemKind.boxSet.localizedCountLabel(count)
            case let .library(item):
                switch item.collectionType {
                case .movies:
                    BaseItemKind.movie.localizedCountLabel(count)
                case .tvshows:
                    BaseItemKind.series.localizedCountLabel(count)
                default:
                    L10n.itemCountLabel(count)
                }
            case .favorites:
                L10n.itemCountLabel(count)
            case .liveTV:
                L10n.itemCountLabel(count)
            }
        }
    }
}
