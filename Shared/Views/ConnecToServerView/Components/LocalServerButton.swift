//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import SwiftUI

extension ConnectToServerView {

    struct LocalServerButton: View {

        let server: ServerState
        let storedServer: ServerState?
        let action: () -> Void

        private var addressStatus: String {
            guard let storedServer else {
                return L10n.serverAddressAvailable
            }

            if storedServer.currentURL == server.currentURL {
                return L10n.serverAddressCurrent
            } else if storedServer.urls.contains(server.currentURL) {
                return L10n.serverAddressSaved
            } else {
                return L10n.serverAddressNew
            }
        }

        var body: some View {
            Button(action: action) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 8) {
                            Text(server.name)
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text(addressStatus)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondarySystemFill)
                                .clipShape(Capsule())
                        }

                        Text(server.currentURL.absoluteString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.body)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
                #if os(tvOS)
                .padding()
                #endif
            }
            .foregroundStyle(.primary, .secondary)
            .buttonStyle(.platformCard)
        }
    }
}
