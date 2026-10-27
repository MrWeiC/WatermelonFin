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
    private var duplicateServer: ServerState? = nil
    @State
    private var isShowingManualAddress: Bool = false
    @State
    private var isPresentingDuplicateServer: Bool = false
    @State
    private var url: String = ""

    private let timer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()

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

    private var connectSection: some View {
        Section(L10n.connectToServer) {
            manualAddressFields
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
                    Label(L10n.enterServerAddressManually, systemImage: "keyboard")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.platformCard)
            }
        } header: {
            Text(L10n.manualServerAddress)
        } footer: {
            Text(L10n.manualServerAddressDescription)
        }
    }

    // MARK: - Local Servers Section

    private var localServersSection: some View {
        Section {
            if viewModel.localServers.isEmpty {
                Text(L10n.noLocalServersFound)
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
            connectSection

            localServersSection
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarCloseButton(disabled: viewModel.state == .connecting) {
            router.dismiss()
        }
        #else
        SplitLoginWindowView(
            isLoading: viewModel.state == .connecting
        ) {
            localServersSection
        } trailingContentView: {
            manualAddressSection
        }
        #endif
    }

    // MARK: - Body

    var body: some View {
        contentView
            .navigationTitle(L10n.connect)
            .interactiveDismissDisabled(viewModel.state == .connecting)
            .onFirstAppear {
                #if os(iOS)
                isURLFocused = true
                #endif
                viewModel.searchForServers()
            }
            .onChange(of: isShowingManualAddress) { _, newValue in
                guard newValue else { return }
                DispatchQueue.main.async {
                    isURLFocused = true
                }
            }
            .onReceive(timer) { _ in
                guard viewModel.state != .connecting else { return }
                viewModel.searchForServers()
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
