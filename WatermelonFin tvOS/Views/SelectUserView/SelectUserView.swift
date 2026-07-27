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
import SwiftUI

struct SelectUserView: View {

    typealias UserItem = (user: UserState, server: ServerState)

    // MARK: - Defaults

    @Default(.selectUserUseSplashscreen)
    private var selectUserUseSplashscreen
    @Default(.selectUserAllServersSplashscreen)
    private var selectUserAllServersSplashscreen
    @Default(.selectUserServerSelection)
    private var serverSelection

    // MARK: - State & Environment Objects

    @Router
    private var router

    // MARK: - Select User Variables

    @State
    private var isEditingUsers: Bool = false
    @State
    private var pin: String = ""
    @State
    private var scrollViewOffset: CGFloat = 0
    @State
    private var selectedUsers: Set<UserState> = []
    @State
    private var selectedPinUserItem: UserItem? = nil

    @FocusState
    private var focusedUserID: String?
    @FocusState
    private var focusedBottomBarItem: BottomBarItem?

    // MARK: - Dialog States

    @State
    private var isPresentingConfirmDeleteUsers = false
    @State
    private var isPresentingLocalPin: Bool = false

    @StateObject
    private var viewModel = SelectUserViewModel()

    private var selectedServer: ServerState? {
        serverSelection.server(from: viewModel.servers.keys)
    }

    private var splashScreenImageSources: [ImageSource] {
        switch (serverSelection, selectUserAllServersSplashscreen) {
        case (.all, .all):
            return viewModel
                .servers
                .keys
                .shuffled()
                .map(\.splashScreenImageSource)

        // need to evaluate server with id selection first
        case let (.server(id), _), let (.all, .server(id)):
            guard let server = viewModel
                .servers
                .keys
                .first(where: { $0.id == id }) else { return [] }

            return [server.splashScreenImageSource]
        }
    }

    private var userItems: [UserItem] {
        switch serverSelection {
        case .all:
            return viewModel.servers
                .map { server, users in
                    users.map { (server: server, user: $0) }
                }
                .flatMap { $0 }
                .sorted(using: \.user.username)
                .reversed()
                .map { UserItem(user: $0.user, server: $0.server) }
        case let .server(id: id):
            guard let server = viewModel.servers.keys.first(where: { server in server.id == id }) else {
                return []
            }

            guard let users = viewModel.servers[server] else {
                return []
            }

            return users
                .sorted(using: \.username)
                .map { UserItem(user: $0, server: server) }
        }
    }

    private var userSelectionDescription: String {
        if userItems.isEmpty {
            L10n.addExistingUserStartDescription
        } else {
            L10n.selectUserDescription
        }
    }

    private var userSelectionTitle: String {
        if userItems.isEmpty {
            L10n.signInExistingJellyfinUser
        } else {
            L10n.selectUser
        }
    }

    // MARK: - Focus

    enum BottomBarItem: Hashable {
        case addUser
        case serverSelection
        case advanced
    }

    private func addUserSelected(server: ServerState) {
        focusedBottomBarItem = nil
        router.route(to: .userSignIn(server: server))
    }

    private func delete(user: UserState) {
        viewModel.deleteUsers([user])
    }

    private func deleteSelectedUsers() {
        guard selectedUsers.isNotEmpty else { return }

        if selectedUsers.count == 1 {
            viewModel.deleteUsers(selectedUsers)
            selectedUsers.removeAll()
        } else {
            isPresentingConfirmDeleteUsers = true
        }
    }

    // MARK: - Select User(s)

    private func select(user: UserState, server: ServerState, needsPin: Bool = true) {
        selectedUsers.insert(user)

        guard user.hasAccessToken else {
            selectedUsers.removeAll()
            router.route(to: .userSignIn(server: server, reauthenticatingUser: user))
            return
        }

        switch user.accessPolicy {
        case .requireDeviceAuthentication:
            // Do nothing, no device authentication on tvOS
            break
        case .requirePin:
            if needsPin {
                selectedPinUserItem = (user: user, server: server)
                isPresentingLocalPin = true
                return
            }
        case .none: ()
        }

        viewModel.signIn(user, server: server, pin: pin)
    }

    // MARK: - Grid Content View

    private var userGridColumnCount: Int {
        max(1, min(userItems.count, 5))
    }

    private var userGridMaxWidth: CGFloat {
        let itemWidth: CGFloat = 260
        let itemSpacing = EdgeInsets.edgePadding

        return CGFloat(userGridColumnCount) * itemWidth
            + CGFloat(userGridColumnCount - 1) * itemSpacing
    }

    private var userGrid: some View {
        CenteredLazyVGrid(
            data: userItems,
            id: \.user.id,
            columns: userGridColumnCount,
            spacing: EdgeInsets.edgePadding
        ) { gridItem in
            let user: UserState = gridItem.user
            let server: ServerState = gridItem.server

            UserGridButton(
                user: user,
                server: server,
                showServer: serverSelection == .all,
                focusedUserID: $focusedUserID
            ) {
                if isEditingUsers {
                    selectedUsers.toggle(value: user)
                } else {
                    select(user: user, server: server)
                }
            } onDelete: {
                delete(user: user)
            }
            .isSelected(selectedUsers.contains(user))
        }
        .frame(maxWidth: userGridMaxWidth)
    }

    private var addUserButtonGrid: some View {
        AddUserGridButton(
            selectedServer: selectedServer,
            servers: viewModel.servers.keys
        ) { server in
            addUserSelected(server: server)
        }
    }

    private var selectionHeader: some View {
        VStack(spacing: 12) {
            Text(userSelectionTitle)
                .font(.title.weight(.semibold))

            Text(userSelectionDescription)
                .font(userItems.isEmpty ? .body : .callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: userItems.isEmpty ? 680 : 760)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, userItems.isEmpty ? 30 : 44)
    }

    // MARK: - User View

    private var contentView: some View {
        VStack {
            ZStack {
                Color.clear

                VStack(spacing: 0) {

                    Color.clear
                        .frame(height: userItems.isEmpty ? 70 : 50)

                    selectionHeader

                    Group {
                        if userItems.isEmpty {
                            addUserButtonGrid
                        } else {
                            userGrid
                        }
                    }
                    .focusSection()
                }
                .scrollIfLargerThanContainer(padding: 100)
                .scrollViewOffset($scrollViewOffset)
            }
            .isEditing(isEditingUsers)

            SelectUserBottomBar(
                isEditing: $isEditingUsers,
                serverSelection: $serverSelection,
                focusedItem: $focusedBottomBarItem,
                selectedServer: selectedServer,
                servers: viewModel.servers.keys,
                areUsersSelected: selectedUsers.isNotEmpty,
                hasUsers: userItems.isNotEmpty
            ) {
                addUserSelected(server: $0)
            } onDelete: {
                deleteSelectedUsers()
            } toggleAllUsersSelected: {
                if selectedUsers.isNotEmpty {
                    selectedUsers.removeAll()
                } else {
                    selectedUsers.insert(contentsOf: userItems.map(\.user))
                }
            } onMoveUp: {
                focusFirstUserIfNeeded(force: true)
            }
            .focusSection()
        }
        .animation(.linear(duration: 0.1), value: scrollViewOffset)
        .environment(\.isOverComplexContent, true)
        .background {
            if selectUserUseSplashscreen, splashScreenImageSources.isNotEmpty {
                ZStack {
                    ImageView(splashScreenImageSources)
                        .pipeline(.WatermelonFin.local)
                        .aspectRatio(contentMode: .fill)
                        .id(splashScreenImageSources)
                        .transition(.opacity)
                        .animation(.linear, value: splashScreenImageSources)

                    Color.black
                        .opacity(0.9)
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Connect to Server View

    private var connectToServerView: some View {
        VStack(spacing: 50) {
            Text(L10n.connectToJellyfinServerStart)
                .font(.body)
                .frame(minWidth: 50, maxWidth: 500)
                .multilineTextAlignment(.center)

            Button {
                router.route(to: .connectToServer)
            } label: {
                Text(L10n.connect)
                    .font(.callout)
                    .fontWeight(.bold)
                    .frame(width: 400, height: 75)
                    .background(Color.watermelonRed)
            }
            .buttonStyle(.card)
        }
    }

    // MARK: - Functions

    private func didDelete(_ server: ServerState) {
        viewModel.getServers()

        if case let SelectUserServerSelection.server(id: id) = serverSelection, server.id == id {
            if viewModel.servers.keys.count == 1, let first = viewModel.servers.keys.first {
                serverSelection = .server(id: first.id)
            } else {
                serverSelection = .all
            }
        }
    }

    private func focusFirstUserIfNeeded(force: Bool = false) {
        guard !isEditingUsers else { return }
        guard let firstUserID = userItems.first?.user.id else { return }

        if !force,
           let focusedUserID,
           userItems.contains(where: { $0.user.id == focusedUserID })
        {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedBottomBarItem = nil
            focusedUserID = firstUserID
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if viewModel.servers.isEmpty {
                connectToServerView
            } else {
                contentView
            }
        }
        .ignoresSafeArea()
        .navigationBarBranding()
        .onAppear {
            viewModel.getServers()
            focusFirstUserIfNeeded(force: true)
        }
        .onChange(of: isEditingUsers) {
            guard !isEditingUsers else { return }
            selectedUsers.removeAll()
            focusFirstUserIfNeeded(force: true)
        }
        .onChange(of: userItems.map(\.user.id)) {
            focusFirstUserIfNeeded()
        }
        .onChange(of: focusedUserID) { _, newValue in
            if newValue != nil {
                focusedBottomBarItem = nil
            }
        }
        .onChange(of: isPresentingLocalPin) {
            if isPresentingLocalPin {
                pin = ""
            } else {
                selectedUsers.removeAll()
                selectedPinUserItem = nil
            }
        }
        .onChange(of: viewModel.servers.keys) {
            let newValue: [ServerState] = Array(viewModel.servers.keys)

            if case let SelectUserServerSelection.server(id: id) = serverSelection,
               !newValue.contains(where: { $0.id == id })
            {
                if newValue.count == 1, let firstServer = newValue.first {
                    let newSelection: SelectUserServerSelection = .server(id: firstServer.id)
                    serverSelection = newSelection
                    selectUserAllServersSplashscreen = newSelection
                } else {
                    serverSelection = .all
                    selectUserAllServersSplashscreen = .all
                }
            }
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case let .expiredSession(user, server):
                selectedUsers.removeAll()
                router.route(to: .userSignIn(server: server, reauthenticatingUser: user))
            case let .signedIn(user):
                Defaults[.lastSignedInUserID] = .signedIn(userID: user.id)
                Container.shared.currentUserSession.reset()
                Notifications[.didSignIn].post()
            }
        }
        .onNotification(.didConnectToServer) { server in
            viewModel.getServers()
            serverSelection = .server(id: server.id)

            // A rediscovered address for a saved server retains its users and
            // access tokens. Let the user select that saved account instead of
            // forcing a password sign-in.
            if server.userIDs.isEmpty {
                router.route(to: .userSignIn(server: server))
            }
        }
        .onNotification(.didChangeCurrentServerURL) { _ in
            viewModel.getServers()
        }
        .onNotification(.didDeleteServer) { _ in
            viewModel.getServers()
        }
        .confirmationDialog(
            Text(L10n.deleteUser),
            isPresented: $isPresentingConfirmDeleteUsers
        ) {
            Button(L10n.delete, role: .destructive) {
                let users = selectedUsers
                selectedUsers.removeAll()
                viewModel.deleteUsers(users)
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: {
            if selectedUsers.count == 1, let first = selectedUsers.first {
                let message: String = L10n.deleteUserSingleConfirmation(first.username)
                Text(message)
            } else {
                let message: String = L10n.deleteUserMultipleConfirmation(selectedUsers.count)
                Text(message)
            }
        }
        .alert(L10n.signIn, isPresented: $isPresentingLocalPin) {

            Backport.textField(L10n.pin, text: $pin)
                .keyboardType(.numberPad)

            Button(L10n.signIn) {
                guard let selectedPinUserItem else {
                    assertionFailure("User not selected")
                    return
                }
                select(
                    user: selectedPinUserItem.user,
                    server: selectedPinUserItem.server,
                    needsPin: false
                )
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: {
            if let user = selectedPinUserItem?.user, user.pinHint.isNotEmpty {
                Text(user.pinHint)
            } else {
                let username = selectedPinUserItem?.user.username ?? .emptyDash

                Text(L10n.enterPinForUser(username))
            }
        }
        .errorMessage($viewModel.error)
    }
}
