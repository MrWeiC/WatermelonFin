//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import UIKit

extension UIScreen {

    /// The screen the app is currently shown on. A folding iPhone has two, so
    /// there is no single main screen to assume.
    static var current: UIScreen {
        UIApplication.shared.keyWindow?.windowScene?.screen ?? .main
    }

    func scale(_ x: Int) -> Int {
        Int(nativeScale) * x
    }

    func scale(_ x: CGFloat) -> Int {
        Int(nativeScale * x)
    }
}
