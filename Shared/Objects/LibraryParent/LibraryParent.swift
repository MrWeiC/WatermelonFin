//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

protocol LibraryParent: Displayable, Hashable, Identifiable<String?> {

    /// The type of the library, reusing `BaseItemKind` for some
    /// ease of provided variety like `folder` and `userView`.
    var libraryType: BaseItemKind? { get }

    /// The `BaseItemKind` types that this library parent
    /// support. Mainly used for `.folder` support.
    ///
    /// When using filters, this is used to determine the initial
    /// set of supported types and then
    var supportedItemTypes: [BaseItemKind] { get }

    /// Modifies the parameters for the items request per this library parent.
    func setParentParameters(_ parameters: Paths.GetItemsByUserIDParameters) -> Paths.GetItemsByUserIDParameters
}

extension LibraryParent {

    var localizedLibraryDisplayTitle: String {
        if let item = self as? BaseItemDto {
            return item.localizedCollectionDisplayTitle
        } else {
            return displayTitle.localizedDefaultLibraryDisplayTitle
        }
    }

    var localizedLatestLibraryTitle: String {
        L10n.latestWithString(localizedLibraryDisplayTitle)
    }

    var supportedItemTypes: [BaseItemKind] {
        switch libraryType {
        case .folder:
            BaseItemKind.supportedCases
                .appending([.folder, .collectionFolder])
        default:
            BaseItemKind.supportedCases
        }
    }

    func setParentParameters(_ parameters: Paths.GetItemsByUserIDParameters) -> Paths.GetItemsByUserIDParameters {

        guard let id else { return parameters }

        var parameters = parameters
        parameters.includeItemTypes = supportedItemTypes

        switch libraryType {
        case .boxSet, .collectionFolder, .playlist, .userView:
            parameters.parentID = id
        case .folder:
            parameters.parentID = id
            parameters.isRecursive = nil
        case .person:
            parameters.personIDs = [id]
        case .studio:
            parameters.studioIDs = [id]
        default: ()
        }

        // A parent must never appear in its own child query. Some Jellyfin
        // responses include it for collection-related item type filters,
        // which otherwise allows the same screen to be pushed indefinitely.
        if parameters.parentID == id {
            var excludedItemIDs = parameters.excludeItemIDs ?? []
            if !excludedItemIDs.contains(id) {
                excludedItemIDs.append(id)
            }
            parameters.excludeItemIDs = excludedItemIDs
        }

        return parameters
    }
}

extension String {

    var localizedDefaultLibraryDisplayTitle: String {
        switch trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "box set", "box sets", "boxsets", "collection", "collections":
            L10n.collections
        case "folder", "folders":
            L10n.folders
        case "film", "films", "movie", "movies":
            L10n.movies
        case "music video", "music videos":
            L10n.musicVideos
        case "playlist", "playlists":
            PlaylistL10n.playlists
        case "series", "show", "shows", "tv series", "tv show", "tv shows":
            L10n.series
        default:
            self
        }
    }
}
