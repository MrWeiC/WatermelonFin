//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct _UnmaskSecureField: View {
    let title: String
    @Binding
    var text: String
    @State
    private var revealed = false

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        HStack {
            Group {
                if revealed { TextField(title, text: $text) }
                else { SwiftUI.SecureField(title, text: $text) }
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
            Button { revealed.toggle() } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
            }.accessibilityLabel(L10n.password)
        }
    }
}
