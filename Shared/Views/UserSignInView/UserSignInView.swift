//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionVGrid
import Defaults
import Factory
import JellyfinAPI
import Logging
import SwiftUI

struct UserSignInView: View {

    private enum Field: Hashable {
        case username
        case password
    }

    @Default(.accentColor)
    private var accentColor

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction
    @Environment(\.quickConnectAction)
    private var quickConnectAction

    @FocusState
    private var focusedTextField: Field?

    @Router
    private var router

    @State
    private var accessPolicy: UserAccessPolicy = .none
    @State
    private var existingUser: UserSignInViewModel.UserStateDataPair? = nil
    @State
    private var isPresentingExistingUser: Bool = false
    @State
    private var password: String = ""
    @State
    private var pinHint: String = ""
    @State
    private var username: String = ""

    @StateObject
    private var viewModel: UserSignInViewModel

    private let reauthenticatingUser: UserState?

    private let logger = Logger.watermelonfin()

    init(
        server: ServerState,
        reauthenticatingUser: UserState? = nil
    ) {
        self.reauthenticatingUser = reauthenticatingUser
        self._viewModel = StateObject(wrappedValue: UserSignInViewModel(server: server))
    }

    private func handleEvent(_ event: UserSignInViewModel._Event) {
        switch event {
        case let .connected(user):
            guard let authenticationAction else {
                return
            }
            viewModel.save(
                user: user,
                authenticationAction: (
                    authenticationAction,
                    accessPolicy,
                    accessPolicy.createReason(
                        user: user.state.state
                    )
                ),
                evaluatedPolicyMap: .init(action: processEvaluatedPolicy)
            )
        case let .existingUser(existingUser):
            if existingUser.state.state.id == reauthenticatingUser?.id {
                saveExistingUser(
                    existingUser,
                    replaceForAccessToken: true
                )
                return
            }

            self.existingUser = existingUser
            self.isPresentingExistingUser = true
        case let .saved(user):
            UIDevice.feedback(.success)

            router.dismiss()
            Defaults[.lastSignedInUserID] = .signedIn(userID: user.id)

            Container.shared.currentUserSession.reset()
            Notifications[.didSignIn].post()
        }
    }

    private var isReauthenticating: Bool {
        reauthenticatingUser != nil
    }

    private var signInButtonTitle: String {
        isReauthenticating ? L10n.signIn : L10n.addUser
    }

    private var signInDescription: String {
        isReauthenticating ? L10n.reauthenticateJellyfinUserDescription : L10n.signInExistingJellyfinUserDescription
    }

    private var signInHeader: String {
        if let reauthenticatingUser {
            L10n.reauthenticateJellyfinUserOnServer(
                reauthenticatingUser.username,
                viewModel.server.name
            )
        } else {
            L10n.addExistingJellyfinUserToServer(viewModel.server.name)
        }
    }

    private var signInTitle: String {
        isReauthenticating ? L10n.reauthenticateJellyfinUser : L10n.signInExistingJellyfinUser
    }

    private func saveExistingUser(
        _ existingUser: UserSignInViewModel.UserStateDataPair,
        replaceForAccessToken: Bool
    ) {
        guard let authenticationAction else { return }

        let userState: UserState = existingUser.state.state
        let existingUserAccessPolicy: UserAccessPolicy = userState.accessPolicy

        viewModel.saveExisting(
            user: existingUser,
            replaceForAccessToken: replaceForAccessToken,
            authenticationAction: (
                authenticationAction,
                existingUserAccessPolicy,
                existingUserAccessPolicy.authenticateReason(
                    user: userState
                )
            ),
            evaluatedPolicyMap: .init(action: processEvaluatedPolicy)
        )
    }

    private func runQuickConnect() {
        Task {
            do {
                guard let secret = try await quickConnectAction?(client: viewModel.server.client) else {
                    logger.critical("QuickConnect called without necessary action!")
                    throw ErrorMessage(L10n.unknownError)
                }
                await viewModel.signInQuickConnect(
                    secret: secret
                )
            } catch is CancellationError {
                // ignore
            } catch {
                logger.error("QuickConnect failed with error: \(error.localizedDescription)")
                await viewModel.error(ErrorMessage(L10n.taskFailed))
            }
        }
    }

    private func processEvaluatedPolicy(
        _ evaluatedPolicy: any EvaluatedLocalUserAccessPolicy
    ) -> any EvaluatedLocalUserAccessPolicy {
        if let pinPolicy = evaluatedPolicy as? PinEvaluatedUserAccessPolicy {
            return PinEvaluatedUserAccessPolicy(
                pin: pinPolicy.pin,
                pinHint: pinHint
            )
        }

        return evaluatedPolicy
    }

    // MARK: - Sign In Section

    @ViewBuilder
    private var signInSection: some View {
        Section {
            TextField(L10n.username, text: $username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedTextField, equals: .username)
                .disabled(isReauthenticating)
                .onSubmit {
                    focusedTextField = .password
                }
            #if os(tvOS)
                .frame(minHeight: 60)
            #endif

            SecureField(
                L10n.password,
                text: $password,
                maskToggle: .enabled
            )
            .onSubmit {
                focusedTextField = nil

                viewModel.signIn(
                    username: username,
                    password: password
                )
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focusedTextField, equals: .password)
            #if os(tvOS)
                .frame(minHeight: 60)
            #endif
        } header: {
            Text(signInHeader)
        } footer: {
            switch accessPolicy {
            case .requireDeviceAuthentication:
                Label(L10n.userDeviceAuthRequiredDescription, systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
            case .requirePin:
                Label(L10n.userPinRequiredDescription, systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
            case .none:
                Text(signInDescription)
            }
        }

        if case .signingIn = viewModel.state {
            Button(L10n.cancel, role: .cancel) {
                viewModel.cancel()
            }
            .buttonStyle(.primary)
            .frame(height: 64)
        } else {
            Button(signInButtonTitle) {
                viewModel.signIn(
                    username: username,
                    password: password
                )
            }
            .buttonStyle(.primary)
            .frame(height: 64)
            .disabled(username.isEmpty)
            .foregroundStyle(
                accentColor.overlayColor,
                accentColor
            )
            .opacity(username.isEmpty ? 0.5 : 1)
        }

        if viewModel.isQuickConnectEnabled {
            Section {
                Button(action: runQuickConnect) {
                    Label(L10n.quickConnect, systemImage: "bolt.horizontal")
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.primary)
                .frame(height: 64)
                .disabled(viewModel.state == .signingIn)
            }
        }

        #if os(tvOS)
        if viewModel.state != .signingIn {
            Button(L10n.cancel) {
                router.dismiss()
            }
            .buttonStyle(.primary)
            .frame(height: 64)
        }
        #endif

        if let disclaimer = viewModel.serverDisclaimer {
            Section(L10n.disclaimer) {
                Text(disclaimer)
                    .font(.callout)
            }
        }
    }

    // MARK: - Public Users Section

    private var publicUsersSection: some View {
        Section {
            if viewModel.publicUsers.isEmpty {
                Label(L10n.noVisibleUsers, systemImage: "person.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            } else {
                #if os(iOS)
                ForEach(viewModel.publicUsers) { user in
                    PublicUserRow(
                        user: user,
                        client: viewModel.server.client
                    ) {
                        username = user.name ?? ""
                        password = ""
                        focusedTextField = .password
                    }
                }
                #else
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 4),
                    spacing: 30
                ) {
                    ForEach(viewModel.publicUsers) { user in
                        PublicUserButton(
                            user: user,
                            client: viewModel.server.client
                        ) {
                            username = user.name ?? ""
                            password = ""
                            focusedTextField = .password
                        }
                        .environment(\.isOverComplexContent, true)
                    }
                }
                #endif
            }
        } header: {
            Text(L10n.visibleUsers)
        } footer: {
            Text(L10n.visibleUsersDescription)
        }
        .disabled(viewModel.state == .signingIn)
    }

    @ViewBuilder
    private var contentView: some View {
        #if os(iOS)
        List {
            signInSection

            publicUsersSection
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarCloseButton(disabled: viewModel.state == .signingIn) {
            router.dismiss()
        }
        .topBarTrailing {
            if viewModel.state == .signingIn || viewModel.background.is(.gettingPublicData) {
                ProgressView()
            }

            Button(L10n.security, systemImage: "gearshape.fill") {
                router.route(
                    to: .userSecurity(
                        pinHint: $pinHint,
                        accessPolicy: $accessPolicy
                    )
                )
            }
        }
        #else
        SplitLoginWindowView(
            isLoading: viewModel.state == .signingIn,
            backgroundImageSource: viewModel.server.splashScreenImageSource
        ) {
            signInSection
        } trailingContentView: {
            publicUsersSection
        }
        #endif
    }

    // MARK: - Body

    var body: some View {
        contentView
            .navigationTitle(signInTitle)
            .interactiveDismissDisabled(viewModel.state == .signingIn)
            .onReceive(viewModel.events, perform: handleEvent)
            .onFirstAppear {
                if let reauthenticatingUser {
                    username = reauthenticatingUser.username
                    focusedTextField = .password
                } else {
                    focusedTextField = .username
                }

                viewModel.getPublicData()
            }
            .alert(
                L10n.duplicateUser,
                isPresented: $isPresentingExistingUser,
                presenting: existingUser
            ) { existingUser in
                Button(L10n.continue) {
                    saveExistingUser(
                        existingUser,
                        replaceForAccessToken: false
                    )
                }

                Button(L10n.replace) {
                    saveExistingUser(
                        existingUser,
                        replaceForAccessToken: true
                    )
                }

                Button(L10n.dismiss, role: .cancel)
            } message: { existingUser in
                Text(L10n.duplicateUserSaved(existingUser.state.state.username))
            }
            .errorMessage($viewModel.error)
    }
}
