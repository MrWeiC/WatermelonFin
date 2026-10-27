//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@main
struct LocalPINPolicyTests {
    static func main() {
        precondition(!LocalPINPolicy.isValid(""))
        precondition(!LocalPINPolicy.isValid("123"))
        precondition(LocalPINPolicy.isValid("1234"))
        precondition(LocalPINPolicy.isValid(String(repeating: "1", count: 30)))
        precondition(!LocalPINPolicy.isValid(String(repeating: "1", count: 31)))
        print("Local PIN policy checks passed")
    }
}
