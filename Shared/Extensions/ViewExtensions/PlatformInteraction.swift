//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension View {
    /// Remote focus groups are meaningful on TV; touch layouts retain their own hierarchy.
    @ViewBuilder
    func platformFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }
}

struct PlatformCardButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        Button(configuration).buttonStyle(.card)
        #else
        Button(configuration).buttonStyle(.bordered)
        #endif
    }
}

extension PrimitiveButtonStyle where Self == PlatformCardButtonStyle {
    static var platformCard: PlatformCardButtonStyle {
        .init()
    }
}
