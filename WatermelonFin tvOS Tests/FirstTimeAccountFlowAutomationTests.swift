//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import CoreStore
import Defaults
import Factory
import JellyfinAPI
@testable import WatermelonFin_tvOS
import XCTest

@MainActor
final class FirstTimeAccountFlowAutomationTests: XCTestCase {

    private struct Credentials {
        let serverURL: URL
        let username: String
        let password: String
    }

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testDevServerCanBeAddedFromEmptyLocalState() async throws {
        let credentials = try loadCredentials()

        await prepareDataStack()
        try await resetLocalState()

        XCTAssertTrue(try WatermelonFinStore.dataStack.fetchAll(From<ServerModel>()).isEmpty)
        XCTAssertTrue(try WatermelonFinStore.dataStack.fetchAll(From<UserModel>()).isEmpty)

        let server = try await connectToServer(credentials.serverURL)
        try await verifyRediscoveredAddressSwitch(for: server)

        let user = try await signInAndSaveUser(
            username: credentials.username,
            password: credentials.password,
            server: server
        )
        let selectedUser = try await signInSavedUser(user, server: server)

        let session = UserSession(server: server, user: selectedUser)
        let remoteUser = try await selectedUser.getUserData(server: server)
        try await validateHomeRequests(session: session)

        XCTAssertEqual(session.server.id, server.id)
        XCTAssertEqual(session.user.id, user.id)
        XCTAssertEqual(remoteUser.id, user.id)
        XCTAssertTrue(session.user.hasAccessToken)
    }

    func testDiscoveredAddressAutomaticallyUpdatesSavedServer() async throws {
        await prepareDataStack()
        try await resetLocalState()
        defer {
            try? deleteStoredUsersAndServers()
        }

        let originalURL = try XCTUnwrap(URL(string: "http://192.0.2.20:8096"))
        let rediscoveredURL = try XCTUnwrap(URL(string: "http://192.0.2.21:8096"))
        let server = ServerState(
            urls: [originalURL],
            currentURL: originalURL,
            name: "Test Jellyfin Server",
            id: "test-server-id",
            usersIDs: []
        )

        try WatermelonFinStore.dataStack.perform { transaction in
            let storedServer = transaction.create(Into<ServerModel>())

            storedServer.urls = server.urls
            storedServer.currentURL = server.currentURL
            storedServer.name = server.name
            storedServer.id = server.id
            storedServer.users = []
        }

        let rediscoveredServer = ServerState(
            urls: [rediscoveredURL],
            currentURL: rediscoveredURL,
            name: server.name,
            id: server.id,
            usersIDs: []
        )

        let updatedServer = try await applyDiscoveredAddress(rediscoveredServer)

        XCTAssertEqual(updatedServer.currentURL, rediscoveredURL)
        XCTAssertTrue(updatedServer.urls.contains(originalURL))
        XCTAssertTrue(updatedServer.urls.contains(rediscoveredURL))
    }

    func testDiscoveredAddressWithWrongIdentityDoesNotUpdateSavedServer() async throws {
        await prepareDataStack()
        try await resetLocalState()
        defer { try? deleteStoredUsersAndServers() }
        let originalURL = try XCTUnwrap(URL(string: "http://192.0.2.20:8096"))
        let candidateURL = try XCTUnwrap(URL(string: "http://192.0.2.21:8096"))
        try WatermelonFinStore.dataStack.perform { transaction in
            let stored = transaction.create(Into<ServerModel>())
            stored.id = "expected-server"
            stored.name = "Saved server"
            stored.currentURL = originalURL
            stored.urls = [originalURL]
            stored.users = []
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryPublicInfoProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-Server-ID": "different-server"]
        let viewModel = ConnectToServerViewModel(sessionConfiguration: configuration)
        let rejected = expectation(description: "wrong server identity rejected")
        viewModel.$error.compactMap { $0 }.prefix(1).sink { _ in rejected.fulfill() }.store(in: &cancellables)
        let candidate = ServerState(
            urls: [candidateURL],
            currentURL: candidateURL,
            name: "Saved server",
            id: "expected-server",
            usersIDs: []
        )
        await viewModel.addNewURL(serverState: candidate)
        await fulfillment(of: [rejected], timeout: 5)
        let stored = try XCTUnwrap(try WatermelonFinStore.dataStack.fetchOne(From<ServerModel>().where(\.$id == "expected-server")))
        XCTAssertEqual(stored.currentURL, originalURL)
        XCTAssertEqual(stored.urls, [originalURL])
        XCTAssertEqual(try WatermelonFinStore.dataStack.fetchAll(From<ServerModel>()).count, 1)
    }

    private func loadCredentials() throws -> Credentials {
        let environment = ProcessInfo.processInfo.environment

        let defaults = UserDefaults.standard
        let username = environment["WATERMELONFIN_AUTOMATION_USERNAME"] ?? defaults.string(forKey: "WATERMELONFIN_AUTOMATION_USERNAME")
        let password = environment["WATERMELONFIN_AUTOMATION_PASSWORD"] ?? defaults.string(forKey: "WATERMELONFIN_AUTOMATION_PASSWORD")

        guard let username, username.isNotEmpty,
              let password, password.isNotEmpty
        else {
            throw XCTSkip(
                "Set WATERMELONFIN_AUTOMATION_USERNAME and WATERMELONFIN_AUTOMATION_PASSWORD, or run Scripts/Automation/add_dev_user_from_env.py."
            )
        }

        guard let serverURLString = environment["WATERMELONFIN_AUTOMATION_SERVER_URL"] ??
            defaults.string(forKey: "WATERMELONFIN_AUTOMATION_SERVER_URL"),
            !serverURLString.isEmpty
        else {
            throw XCTSkip("Set WATERMELONFIN_AUTOMATION_SERVER_URL to an explicitly configured test server.")
        }
        guard let serverURL = URL(string: serverURLString),
              ["http", "https"].contains(serverURL.scheme?.lowercased() ?? ""),
              serverURL.host != nil
        else {
            throw XCTSkip("WATERMELONFIN_AUTOMATION_SERVER_URL is not a valid HTTP(S) URL.")
        }

        return Credentials(
            serverURL: serverURL,
            username: username,
            password: password
        )
    }

    private func prepareDataStack() async {
        try? await WatermelonFinStore.setupDataStack()
    }

    private func resetLocalState() async throws {
        Notifications[.didSignOut].post()
        await Task.yield()

        Defaults[.lastSignedInUserID] = .signedOut
        Defaults[.selectUserServerSelection] = .all
        Container.shared.currentUserSession.reset()

        try deleteStoredUsersAndServers()
    }

    private func deleteStoredUsersAndServers() throws {
        let users = try WatermelonFinStore.dataStack
            .fetchAll(From<UserModel>())
            .compactMap(\.state)
        for user in users {
            try user.delete()
        }

        let servers = try WatermelonFinStore.dataStack
            .fetchAll(From<ServerModel>())
            .map(\.state)
        for server in servers {
            try server.delete()
        }
    }

    private func connectToServer(_ serverURL: URL) async throws -> ServerState {
        let viewModel = ConnectToServerViewModel()
        let finished = expectation(description: "server connection finished")

        var connectedServer: ServerState?
        var unexpectedFailure: String?

        viewModel.events
            .sink { event in
                switch event {
                case let .connected(server):
                    connectedServer = server
                    finished.fulfill()
                case .duplicateServer:
                    unexpectedFailure = "Expected an empty local store, but the server already exists."
                    finished.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.$error
            .compactMap { $0 }
            .sink { error in
                unexpectedFailure = error.localizedDescription
                finished.fulfill()
            }
            .store(in: &cancellables)

        await viewModel.connect(url: serverURL.absoluteString)
        await fulfillment(of: [finished], timeout: 30)

        if let unexpectedFailure {
            XCTFail(unexpectedFailure)
        }

        return try XCTUnwrap(connectedServer)
    }

    private func verifyRediscoveredAddressSwitch(for server: ServerState) async throws {
        let rediscoveredURL = try XCTUnwrap(URL(string: "http://192.0.2.10:8096"))
        let rediscoveredServer = ServerState(
            urls: [rediscoveredURL],
            currentURL: rediscoveredURL,
            name: server.name,
            id: server.id,
            usersIDs: []
        )

        let switchedServer = try await applyDiscoveredAddress(rediscoveredServer)
        XCTAssertEqual(switchedServer.id, server.id)
        XCTAssertEqual(switchedServer.currentURL, rediscoveredURL)
        XCTAssertTrue(switchedServer.urls.contains(server.currentURL))
        XCTAssertTrue(switchedServer.urls.contains(rediscoveredURL))

        let restoredServer = ServerState(
            urls: [server.currentURL],
            currentURL: server.currentURL,
            name: server.name,
            id: server.id,
            usersIDs: []
        )

        let restored = try await applyDiscoveredAddress(restoredServer)
        XCTAssertEqual(restored.currentURL, server.currentURL)
        XCTAssertTrue(restored.urls.contains(rediscoveredURL))
    }

    private func applyDiscoveredAddress(_ server: ServerState) async throws -> ServerState {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryPublicInfoProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-Server-ID": server.id]
        configuration.timeoutIntervalForResource = 4
        let viewModel = ConnectToServerViewModel(sessionConfiguration: configuration)
        let connected = expectation(description: "discovered address connected")
        let notified = expectation(description: "current server URL changed")

        var connectedServer: ServerState?
        var notifiedServer: ServerState?
        var unexpectedFailure: String?

        viewModel.events
            .sink { event in
                switch event {
                case let .connected(server):
                    guard connectedServer == nil else { return }
                    connectedServer = server
                    connected.fulfill()
                case .duplicateServer:
                    guard unexpectedFailure == nil, connectedServer == nil else { return }
                    unexpectedFailure = "Expected discovered address to be saved, not re-reported as duplicate."
                    connected.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.$error
            .compactMap { $0 }
            .sink { error in
                guard unexpectedFailure == nil, connectedServer == nil else { return }
                unexpectedFailure = error.localizedDescription
                connected.fulfill()
            }
            .store(in: &cancellables)

        Notifications[.didChangeCurrentServerURL]
            .publisher
            .sink { changedServer in
                guard changedServer.id == server.id else { return }
                guard notifiedServer == nil else { return }
                notifiedServer = changedServer
                notified.fulfill()
            }
            .store(in: &cancellables)

        await viewModel.addNewURL(serverState: server)
        await fulfillment(of: [connected, notified], timeout: 10)

        if let unexpectedFailure {
            XCTFail(unexpectedFailure)
        }

        let connectedResult = try XCTUnwrap(connectedServer)
        let notificationResult = try XCTUnwrap(notifiedServer)
        XCTAssertEqual(notificationResult.currentURL, connectedResult.currentURL)

        let storedServer = try XCTUnwrap(
            try WatermelonFinStore.dataStack.fetchOne(From<ServerModel>().where(\.$id == server.id))?.state
        )
        XCTAssertEqual(storedServer.currentURL, connectedResult.currentURL)
        XCTAssertEqual(storedServer.urls, connectedResult.urls)

        return connectedResult
    }

    private func signInAndSaveUser(
        username: String,
        password: String,
        server: ServerState
    ) async throws -> UserState {
        let viewModel = UserSignInViewModel(server: server)
        let signedIn = expectation(description: "user signed in")

        var connectedUser: UserSignInViewModel.UserStateDataPair?
        var unexpectedFailure: String?

        viewModel.events
            .sink { event in
                switch event {
                case let .connected(user):
                    connectedUser = user
                    signedIn.fulfill()
                case .existingUser:
                    unexpectedFailure = "Expected an empty local store, but the user already exists."
                    signedIn.fulfill()
                case .saved:
                    break
                }
            }
            .store(in: &cancellables)

        viewModel.$error
            .compactMap { $0 }
            .sink { error in
                unexpectedFailure = error.localizedDescription
                signedIn.fulfill()
            }
            .store(in: &cancellables)

        await viewModel.signIn(username: username, password: password)
        await fulfillment(of: [signedIn], timeout: 30)

        if let unexpectedFailure {
            XCTFail(unexpectedFailure)
        }

        let user = try XCTUnwrap(connectedUser)
        let saved = expectation(description: "user saved")
        var savedUser: UserState?

        viewModel.events
            .sink { event in
                if case let .saved(user) = event {
                    savedUser = user
                    saved.fulfill()
                }
            }
            .store(in: &cancellables)

        await viewModel.save(
            user: user,
            authenticationAction: (
                LocalUserAuthenticationAction { _, _ in EmptyEvaluatedUserAccessPolicy() },
                .none,
                nil
            ),
            evaluatedPolicyMap: .init { $0 }
        )
        await fulfillment(of: [saved], timeout: 10)

        return try XCTUnwrap(savedUser)
    }

    private func signInSavedUser(_ user: UserState, server: ServerState) async throws -> UserState {
        let viewModel = SelectUserViewModel()
        let signedIn = expectation(description: "saved user signed in")

        var selectedUser: UserState?
        var unexpectedFailure: String?

        viewModel.events
            .sink { event in
                switch event {
                case let .signedIn(user):
                    selectedUser = user
                    signedIn.fulfill()
                case .expiredSession:
                    unexpectedFailure = "Expected the saved Jellyfin token to remain valid."
                    signedIn.fulfill()
                case .discoverServers:
                    // Discovery presentation is handled by the app UI. This
                    // helper waits only for the saved-account sign-in result.
                    break
                }
            }
            .store(in: &cancellables)

        viewModel.$error
            .compactMap { $0 }
            .sink { error in
                unexpectedFailure = error.localizedDescription
                signedIn.fulfill()
            }
            .store(in: &cancellables)

        await viewModel.signIn(user, server: server, pin: "")
        await fulfillment(of: [signedIn], timeout: 30)

        if let unexpectedFailure {
            XCTFail(unexpectedFailure)
        }

        return try XCTUnwrap(selectedUser)
    }

    private func validateHomeRequests(session: UserSession) async throws {
        var resumeParameters = Paths.GetResumeItemsParameters()
        resumeParameters.userID = session.user.id
        resumeParameters.enableUserData = true
        resumeParameters.fields = .MinimumFields
        resumeParameters.mediaTypes = [.video]
        resumeParameters.limit = 20

        var itemParameters = Paths.GetItemsByUserIDParameters()
        itemParameters.enableUserData = true
        itemParameters.fields = .MinimumFields
        itemParameters.includeItemTypes = BaseItemKind.supportedCases
        itemParameters.sortOrder = [.ascending]
        itemParameters.sortBy = [ItemSortBy.name.rawValue]
        itemParameters.isRecursive = true
        itemParameters.limit = 20

        _ = try await session.client.send(Paths.getUserViews(parameters: .init(userID: session.user.id)))
        _ = try await session.client.send(Paths.getResumeItems(parameters: resumeParameters))
        _ = try await session.client.send(Paths.getItemsByUserID(userID: session.user.id, parameters: itemParameters))
    }
}

/// Only intercepts reserved documentation addresses; live configured endpoints
/// keep using the actual network. Every mocked response still passes through
/// the real HTTP decoding and Server ID verification path.
private final class DiscoveryPublicInfoProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasPrefix("192.0.2.") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              )
        else { return }
        let data = try! JSONSerialization.data(withJSONObject: [
            "Id": request.value(forHTTPHeaderField: "X-Test-Server-ID") ?? "test-server-id",
            "ServerName": "Test Jellyfin Server",
            "Version": "10.10.0",
        ])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
