//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum PlaylistL10n {

    static let addToPlaylist = localized("addToPlaylist", fallback: "Add to Playlist")
    static let createPlaylist = localized("createPlaylist", fallback: "Create Playlist")
    static let noVideoPlaylists = localized("noVideoPlaylists", fallback: "No video playlists")
    static let playlist = L10n.playlist
    static let playlists = L10n.playlists
    static let removeFromPlaylist = localized("removeFromPlaylist", fallback: "Remove from Playlist")

    private static let bundle = Bundle.main

    private static func localized(_ key: String, fallback: String) -> String {
        bundle.localizedString(forKey: key, value: fallback, table: "Playlist")
    }
}
