//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension View {
    func navigationBarCloseButton(disabled: Bool = false, action: @escaping () -> Void) -> some View {
        toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.close, action: action).disabled(disabled) } }
    }
}
