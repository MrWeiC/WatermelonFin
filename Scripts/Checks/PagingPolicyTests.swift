//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

@main
struct PagingPolicyTests {
    static func main() {
        precondition(PagingPagePolicy.hasNextPage(receivedCount: 20, pageSize: 20))
        precondition(!PagingPagePolicy.hasNextPage(receivedCount: 19, pageSize: 20))
        precondition(!PagingPagePolicy.hasNextPage(receivedCount: 0, pageSize: 20))
        print("Paging policy checks passed")
    }
}
