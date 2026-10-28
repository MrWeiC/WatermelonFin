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

struct ConnectToServerView: View {

    @Default(.accentColor)
    private var accentColor

    @FocusState
    private var isURLFocused: Bool

    @Router
    private var router

    @StateObject
    private var viewModel = ConnectToServerViewModel()

    @State
    private var hasRequestedSearch = false

    @Environment(\.openURL)
    private var openURL

    @State
    private var duplicateServer: ServerState? = nil
    @State
    private var isShowingManualAddress: Bool = !ServerDiscovery.isEnabled
    @State
    private var isPresentingDuplicateServer: Bool = false
    @State
    private var url: String = ""

    @Environment(\.scenePhase)
    private var scenePhase

    private var canConnectManually: Bool {
        url.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty
    }

    private func continueToSignIn(server: ServerState) {
        UIDevice.feedback(.success)
        #if WATERMELONFIN_PHONE
        Notifications[.didConnectToServer].post(server)
        if server.userIDs.isEmpty {
            // Keep the current presentation alive while pushing sign-in. Replacing
            // a fullscreen route during its dismissal can discard the new route.
            router.route(to: .userSignIn(server: server), style: .push(.automatic))
        } else {
            router.dismiss()
        }
        #else
        router.dismiss()

        DispatchQueue.main.async {
            Notifications[.didConnectToServer].post(server)
        }
        #endif
    }

    private func onEvent(_ event: ConnectToServerViewModel._Event) {
        switch event {
        case let .connected(server):
            continueToSignIn(server: server)
        case let .duplicateServer(server):
            UIDevice.feedback(.warning)
            duplicateServer = server
            isPresentingDuplicateServer = true
        }
    }

    @ViewBuilder
    private var manualAddressFields: some View {
        TextField(L10n.serverURL, text: $url)
            .accessibilityIdentifier("mobile.server.address")
            .disableAutocorrection(true)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .focused($isURLFocused)
        #if os(tvOS)
            .frame(minHeight: 60)
        #endif

        if viewModel.state == .connecting {
            Button(L10n.cancel, role: .cancel) {
                viewModel.cancel()
            }
            .buttonStyle(.primary)
            .frame(height: 64)
        } else {
            Button(L10n.connect) {
                isURLFocused = false
                viewModel.connect(url: url)
            }
            .buttonStyle(.primary)
            .frame(height: 64)
            .disabled(!canConnectManually)
            .foregroundStyle(
                accentColor.overlayColor,
                accentColor
            )
            .opacity(canConnectManually ? 1 : 0.5)
        }
    }

    private var savedServersSection: some View {
        Section {
            ForEach(viewModel.storedServersByID.values.sorted { $0.name < $1.name }) { server in
                Button {
                    viewModel.retrySavedServer(server)
                } label: {
                    Label(server.name, systemImage: "server.rack")
                }
                .disabled(viewModel.state == .connecting || viewModel.isRecovering)
            }
            if viewModel.isRecovering { ProgressView(L10n.serverLookingForSaved) }
        } header: {
            if !viewModel.storedServersByID.isEmpty { Text(L10n.serverSavedList) }
        } footer: {
            if !viewModel.storedServersByID.isEmpty {
                Text(L10n.serverSavedHelp)
            }
        }
    }

    private var manualAddressSection: some View {
        Section {
            if isShowingManualAddress {
                manualAddressFields
            } else {
                Button {
                    isShowingManualAddress = true
                } label: {
                    Label(L10n.serverManualOptional, systemImage: "keyboard")
                        .accessibilityIdentifier("server.manualAddress")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.platformCard)
            }
        } header: {
            Text(L10n.manualServerAddress)
        } footer: {
            Text(
                L10n.serverManualHelp
            )
        }
    }

    // MARK: - Local Servers Section

    private var localServersSection: some View {
        Section {
            if viewModel.isSearching {
                ProgressView(L10n.serverSearching)
                    .accessibilityIdentifier("server.searching")
            }
            if !hasRequestedSearch {
                Text(L10n.serverPermissionHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if viewModel.localServers.isEmpty && !viewModel.isSearching {
                Text(viewModel
                    .discoveryFailed ? L10n.serverSearchUnavailable :
                    L10n.serverSearchEmpty)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(viewModel.localServers) { server in
                    LocalServerButton(
                        server: server,
                        storedServer: viewModel.storedServer(for: server)
                    ) {
                        url = server.currentURL.absoluteString
                        viewModel.connect(url: server.currentURL.absoluteString)
                    }
                }
            }
            #if os(iOS)
            if viewModel.discoveryFailed {
                Button(L10n.serverOpenSettings) {
                    if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
                }
            }
            #endif
            Button(hasRequestedSearch ? L10n.serverSearchAgain : L10n.serverSearchStart, systemImage: "arrow.clockwise") {
                hasRequestedSearch = true
                viewModel.searchForServers()
            }
            .disabled(viewModel.isSearching || viewModel.state == .connecting)
            .accessibilityIdentifier("server.searchAgain")
        } header: {
            Text(L10n.localServers)
        } footer: {
            Text(L10n.localServersDescription)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        #if os(iOS)
        List {
            if ServerDiscovery.isEnabled { localServersSection }

            manualAddressSection

            savedServersSection
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarCloseButton(disabled: viewModel.state == .connecting) {
            router.dismiss()
        }
        #else
        SplitLoginWindowView(
            isLoading: viewModel.state == .connecting
        ) {
            if ServerDiscovery.isEnabled {
                localServersSection
            } else {
                Text(L10n.manualServerAddress)
                    .font(.title2)
                Text(L10n.serverPermissionHelp)
                    .foregroundStyle(.secondary)
            }
        } trailingContentView: {
            manualAddressSection
            savedServersSection
        }
        #endif
    }

    // MARK: - Body

    var body: some View {
        contentView
            .navigationTitle(L10n.connect)
            .interactiveDismissDisabled(viewModel.state == .connecting)
            .onChange(of: isShowingManualAddress) { _, newValue in
                guard newValue else { return }
                DispatchQueue.main.async {
                    isURLFocused = true
                }
            }
            .onDisappear { viewModel.stopSearching() }
            .onChange(of: scenePhase) { _, phase in
                if ServerDiscovery.isEnabled, phase == .active, hasRequestedSearch, viewModel.state != .connecting {
                    viewModel.searchForServers()
                } else if phase != .active { viewModel.stopSearching() }
            }
            .onReceive(viewModel.events, perform: onEvent)
            .onReceive(viewModel.$error) { error in
                guard error != nil else { return }
                UIDevice.feedback(.error)
                #if os(tvOS)
                isShowingManualAddress = true
                #endif
                isURLFocused = true
            }
            .topBarTrailing {
                #if os(iOS)
                if viewModel.state == .connecting {
                    ProgressView()
                }
                #endif
            }
            .alert(
                Text(L10n.server),
                isPresented: $isPresentingDuplicateServer,
                presenting: duplicateServer
            ) { server in
                Button(L10n.dismiss, role: .destructive)

                Button(L10n.addURL) {
                    viewModel.addNewURL(serverState: server)
                }
            } message: { server in
                Text(L10n.serverNewAddressPrompt(server.name, server.currentURL.absoluteString))
            }
            .errorMessage($viewModel.error)
    }
}
