//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct MediaStreamInfoView: View {
    let mediaStream: MediaStream
    var body: some View {
        Form {
            Text(mediaStream.displayTitle).font(.headline)
            if let codec = mediaStream.codec { LabeledContent(L10n.type, value: codec) }
            if let language = mediaStream.language { LabeledContent(L10n.language, value: language) }
            if let bitrate = mediaStream.bitRate { LabeledContent(L10n.playbackQuality, value: "\(bitrate)") }
        }.navigationTitle(L10n.info)
    }
}
