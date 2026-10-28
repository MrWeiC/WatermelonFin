//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import JellyfinAPI
import LocalAuthentication
import SwiftUI

struct SelectUserView: View {
    @StateObject
    private var viewModel = SelectUserViewModel()
    @Router
    private var router
    @State
    private var pin = ""
    @State
    private var pinUser: UserState?
    @State
    private var pinServer: ServerState?
    @State
    private var showPIN = false

    var body: some View {
        List {
            Section {
                Image(.watermelonfinLogo).resizable().scaledToFit().frame(height: 90).frame(maxWidth: .infinity)
            }.listRowBackground(Color.clear)
            ForEach(viewModel.servers.keys, id: \.id) { server in
                Section(server.name) {
                    ForEach(viewModel.servers[server] ?? [], id: \.id) { user in
                        Button(user.username, systemImage: "person.crop.circle") {
                            if user.accessPolicy == .requirePin {
                                pinUser = user
                                pinServer = server
                                pin = ""
                                showPIN = true
                            } else { signIn(user, server: server) }
                        }
                        .swipeActions {
                            Button(L10n.delete, role: .destructive) { viewModel.deleteUsers([user]) }
                        }
                    }
                    Button(L10n.addUser, systemImage: "person.badge.plus") { router.route(to: .userSignIn(server: server)) }
                }
            }
            Button(L10n.addServer, systemImage: "plus") { router.route(to: .connectToServer) }
                .accessibilityIdentifier("mobile.account.addServer")
        }
        .navigationTitle(L10n.signIn)
        .onFirstAppear { viewModel.getServers() }
        .onNotification(.didConnectToServer) { _ in
            viewModel.getServers()
        }
        .onNotification(.didChangeCurrentServerURL) { _ in viewModel.getServers() }
        .onNotification(.didDeleteServer) { _ in viewModel.getServers() }
        .onReceive(viewModel.events) { event in
            switch event {
            case .discoverServers:
                router.route(to: .connectToServer)
            case let .signedIn(user):
                Defaults[.lastSignedInUserID] = .signedIn(userID: user.id)
                Container.shared.currentUserSession.reset()
                Notifications[.didSignIn].post()
            case let .expiredSession(user, server):
                router.route(to: .userSignIn(server: server, reauthenticatingUser: user))
            default: break
            }
        }
        .alert(L10n.pin, isPresented: $showPIN) {
            SecureField(L10n.pin, text: $pin).keyboardType(.numberPad)
            Button(L10n.signIn) {
                if let user = pinUser, let server = pinServer { viewModel.signIn(user, server: server, pin: pin) }
            }
            Button(L10n.cancel, role: .cancel) {}
        }
        .errorMessage($viewModel.error)
    }

    private func signIn(_ user: UserState, server: ServerState) {
        Task {
            do {
                if user.accessPolicy == .requireDeviceAuthentication {
                    let context = LAContext()
                    try await context.evaluatePolicy(
                        .deviceOwnerAuthentication,
                        localizedReason: user.accessPolicy.authenticateReason(user: user) ?? L10n.signIn
                    )
                }
                await viewModel.signIn(user, server: server, pin: "")
            } catch {
                viewModel.error = error
            }
        }
    }
}
