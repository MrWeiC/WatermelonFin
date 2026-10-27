//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct FilterView: View {
    @ObservedObject
    var viewModel: FilterViewModel
    let type: ItemFilterType
    var body: some View {
        List {
            Button(L10n.reset) { viewModel.send(.reset(type)) }
            ForEach(viewModel.allFilters[keyPath: type.collectionAnyKeyPath], id: \.value) { filter in
                Button {
                    var selection = viewModel.currentFilters[keyPath: type.collectionAnyKeyPath]
                    if type.selectorType == .single { selection = [filter] }
                    else if selection.contains(filter) { selection.removeAll { $0 == filter } }
                    else { selection.append(filter) }
                    viewModel.send(.update(type, selection))
                } label: {
                    HStack {
                        Text(filter.displayTitle)
                        Spacer()
                        if viewModel.currentFilters[keyPath: type.collectionAnyKeyPath].contains(filter) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }.navigationTitle(type.displayTitle)
    }
}

struct LocalUserAccessPolicyView: View {
    @Binding
    var pinHint: String
    @Binding
    var accessPolicy: UserAccessPolicy
    var body: some View {
        Form {
            Picker(L10n.security, selection: $accessPolicy) {
                ForEach(UserAccessPolicy.allCases, id: \.self) { Text($0.displayTitle).tag($0) }
            }
            if accessPolicy == .requirePin { TextField(L10n.hint, text: $pinHint) }
        }.navigationTitle(L10n.security)
    }
}
