//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Waiting UI shared by the mobile MPV and native playback routes.
struct WatermelonPlaybackLoadingView: View {
    @Router
    private var router

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                WatermelonLoadingAnimation(style: .playback)
                    .frame(width: 112, height: 112)
                Text(L10n.retrievingMediaInformation)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Button {
                    router.dismiss()
                } label: {
                    Text(L10n.cancel)
                        .foregroundStyle(Color.watermelonRed)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .overlay {
                            Capsule().stroke(Color.watermelonRed, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }
}
