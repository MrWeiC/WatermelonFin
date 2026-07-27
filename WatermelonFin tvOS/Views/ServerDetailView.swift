//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct EditServerView: View {

    @Router
    private var router

    @Environment(\.isEditing)
    private var isEditing

    @State
    private var isPresentingConfirmDeletion: Bool = false

    @FocusState
    private var isAddressFocused: Bool

    @StateObject
    private var viewModel: ServerConnectionViewModel

    init(server: ServerState) {
        self._viewModel = StateObject(wrappedValue: ServerConnectionViewModel(server: server))
    }

    private var sortedServerURLs: [URL] {
        viewModel.server.urls.sorted(using: \.absoluteString)
    }

    private var serverVersion: String? {
        StoredValues[.Server.publicInfo(id: viewModel.server.id)].version
    }

    private var header: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.watermelonGreen.opacity(0.22))

                Image(systemName: "server.rack")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.watermelonGreen)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.server.name)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(2)

                Text(viewModel.server.currentURL.absoluteString)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var addressMenu: some View {
        Menu {
            ForEach(sortedServerURLs, id: \.self) { url in
                Button {
                    guard viewModel.server.currentURL != url else { return }
                    viewModel.setCurrentURL(to: url)
                } label: {
                    HStack {
                        Text(url.absoluteString)

                        Spacer()

                        if viewModel.server.currentURL == url {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.serverURL)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isAddressFocused ? Color.black.opacity(0.62) : Color.secondary)

                    Text(viewModel.server.currentURL.absoluteString)
                        .font(.body.monospaced())
                        .foregroundStyle(isAddressFocused ? Color.black : Color.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isAddressFocused ? Color.black.opacity(0.62) : Color.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                isAddressFocused ? Color.white : Color.white.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .scaleEffect(isAddressFocused ? 1.035 : 1)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .focused($isAddressFocused)
        .animation(.easeInOut(duration: 0.125), value: isAddressFocused)
        .accessibilityLabel(L10n.serverURL)
        .accessibilityValue(viewModel.server.currentURL.absoluteString)
    }

    @ViewBuilder
    private var compatibilityWarning: some View {
        if !viewModel.server.isVersionCompatible {
            Label(
                L10n.serverVersionWarning(JellyfinClient.sdkVersion.majorMinor.description),
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.yellow)
        }
    }

    private var deleteButton: some View {
        Button {
            isPresentingConfirmDeletion = true
        } label: {
            Text(L10n.delete)
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.card)
        .buttonBorderShape(.roundedRectangle(radius: 14))
    }

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 28) {
                header

                VStack(spacing: 14) {
                    detailRow(L10n.name, value: viewModel.server.name)

                    if let serverVersion {
                        detailRow(L10n.version, value: serverVersion)
                    }

                    addressMenu
                }

                compatibilityWarning

                if isEditing {
                    deleteButton
                }
            }
            .frame(width: 760)
            .padding(.top, 100)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(L10n.server)
        .alert(L10n.deleteServer, isPresented: $isPresentingConfirmDeletion) {
            Button(L10n.delete, role: .destructive) {
                if viewModel.delete() {
                    router.dismiss()
                }
            }
        } message: {
            Text(L10n.confirmDeleteServerAndUsers(viewModel.server.name))
        }
    }
}
