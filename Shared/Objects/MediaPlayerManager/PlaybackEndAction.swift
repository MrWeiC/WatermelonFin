//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Separates failures from deliberate stop/replacement events and natural completion.
enum PlaybackEndAction {
    case ignore
    case finish
    case fail

    static func resolve(isError: Bool, isEOF: Bool, isStopping: Bool, isReady: Bool) -> Self {
        guard !isStopping else { return .ignore }
        if isError { return .fail }
        return isEOF && isReady ? .finish : .ignore
    }
}
