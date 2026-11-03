//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// TV shows library without the unsupported Live TV placeholder.
struct TVTabView: View {
    @StateObject
    private var viewModel = ItemLibraryViewModel(
        filters: .init(itemTypes: [.series])
    )

    var body: some View {
        PagingLibraryView(viewModel: viewModel)
    }
}
