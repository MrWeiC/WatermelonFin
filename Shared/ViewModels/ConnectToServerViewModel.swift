//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import CoreStore
import Factory
import Foundation
import Get
import JellyfinAPI
import OrderedCollections
import Pulse

@MainActor
@Stateful
final class ConnectToServerViewModel: ViewModel {

    @CasePathable
    enum Action {
        case addNewURL(serverState: ServerState)
        case cancel
        case connect(url: String)
        case searchForServers

        var transition: Transition {
            switch self {
            case .addNewURL, .searchForServers: .none
            case .cancel: .to(.initial)
            case .connect: .loop(.connecting)
            }
        }
    }

    enum Event {
        case connected(ServerState)
        case duplicateServer(ServerState)
        case error
    }

    enum State {
        case connecting
        case initial
    }

    @Published
    var localServers: OrderedSet<ServerState> = []
    @Published
    private(set) var isSearching = false
    @Published
    private(set) var storedServersByID: [String: ServerState] = [:]

    @Published
    private(set) var discoveryFailed = false
    @Published
    private(set) var isRecovering = false
    private var recoveryTask: Task<Void, Never>?
    private var failureSubscription: AnyCancellable?
    private let connectionSessionConfiguration: URLSessionConfiguration
    private var discovery: ServerDiscovery?
    private var discoverySubscription: AnyCancellable?
    private var searchTask: Task<Void, Never>?

    deinit {
        searchTask?.cancel()
        recoveryTask?.cancel()
        discovery?.close()
    }

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        connectionSessionConfiguration = configuration
        super.init()
        Task { @MainActor [weak self] in
            self?.refreshStoredServers()
        }
    }

    init(sessionConfiguration: URLSessionConfiguration) {
        connectionSessionConfiguration = sessionConfiguration
        super.init()
        Task { @MainActor [weak self] in self?.refreshStoredServers() }
    }

    func stopSearching() {
        searchTask?.cancel()
        searchTask = nil
        discoverySubscription?.cancel()
        discoverySubscription = nil
        failureSubscription?.cancel()
        failureSubscription = nil
        discovery?.close()
        discovery = nil
        isSearching = false
    }

    @Function(\Action.Cases.connect)
    private func connectToServer(_ input: String) async throws {
        try await performConnection(input, expectedServerID: nil)
    }

    private func performConnection(_ input: String, expectedServerID: String?) async throws {
        let url: URL
        do { url = try ServerAddressInput.url(from: input) }
        catch { throw ErrorMessage(L10n.serverInvalidAddress) }

        // Validate IP address format if host looks like an IP
        if let host = url.host, host.looksLikeIPv4Address, !host.isValidIPv4Address {
            throw ErrorMessage(L10n.invalidIPAddress)
        }

        // Log warning for non-HTTPS connections
        if url.scheme == "http" {
            logger.warning("Connecting to server over insecure HTTP connection: \(url.host ?? "unknown")")
        }

        let client = JellyfinClient.watermelonfinClient(
            configuration: .watermelonfinConfiguration(url: url),
            sessionConfiguration: connectionSessionConfiguration,
            sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.watermelonfin())
        )

        let response = try await client.send(Paths.getPublicSystemInfo)

        guard let name = response.value.serverName,
              let id = response.value.id
        else {
            logger.critical("Missing server data from network call")
            throw ErrorMessage(L10n.unknownError)
        }

        if let expectedServerID,
           !ServerIdentityPolicy.matches(expected: expectedServerID, reported: id)
        {
            throw ErrorMessage(L10n.serverIdentityMismatch)
        }

        let connectionURL = processConnectionURL(
            initial: url,
            response: response.response.url
        )

        let newServerState = ServerState(
            urls: [connectionURL],
            currentURL: connectionURL,
            name: name,
            id: id,
            usersIDs: []
        )

        if let existingServer = existingServer(for: newServerState) {
            // server has same id, but (possible) new URL
            if existingServer.currentURL == newServerState.currentURL {
                events.send(.connected(existingServer))
            } else {
                let updatedServer = try updateStoredAddress(
                    for: existingServer,
                    discoveredServer: newServerState
                )
                events.send(.connected(updatedServer))
            }
        } else {
            try await save(server: newServerState)
            refreshStoredServers()
            events.send(.connected(newServerState))
        }
    }

    /// In the event of redirects, get the new host URL from response
    private func processConnectionURL(initial url: URL, response: URL?) -> URL {

        guard let response else { return url }

        if url.scheme != response.scheme ||
            url.host != response.host
        {
            let newURL = response.absoluteString.trimmingSuffix(
                Paths.getPublicSystemInfo.url?.absoluteString ?? ""
            )
            return URL(string: newURL) ?? url
        }

        return url
    }

    func storedServer(for server: ServerState) -> ServerState? {
        storedServersByID[server.id]
    }

    private func existingServer(for server: ServerState) -> ServerState? {
        if let storedServer = storedServersByID[server.id] {
            return storedServer
        }

        guard let existingServer = try? WatermelonFinStore
            .dataStack
            .fetchOne(From<ServerModel>().where(\.$id == server.id))
        else {
            return nil
        }

        return existingServer.state
    }

    private func refreshStoredServers() {
        let servers = (try? WatermelonFinStore
            .dataStack
            .fetchAll(From<ServerModel>())
            .map(\.state)) ?? []

        storedServersByID = servers.reduce(into: [:]) { partialResult, server in
            partialResult[server.id] = server
        }
    }

    private func save(server: ServerState) async throws {

        let publicInfo = try await server.getPublicSystemInfo()

        try dataStack.perform { transaction in
            let newServer = transaction.create(Into<ServerModel>())

            newServer.urls = server.urls
            newServer.currentURL = server.currentURL
            newServer.name = server.name
            newServer.id = server.id
            newServer.users = []
        }

        StoredValues[.Server.publicInfo(id: server.id)] = publicInfo
    }

    private func updateStoredAddress(
        for existingServer: ServerState,
        discoveredServer: ServerState
    ) throws -> ServerState {
        let newState = try dataStack.perform { transaction in
            guard let editServer = try transaction.fetchOne(From<ServerModel>().where(\.$id == existingServer.id)) else {
                logger.critical("Could not find server to update current url")
                throw ErrorMessage(L10n.internalErrorOccurred)
            }

            editServer.urls.insert(discoveredServer.currentURL)
            editServer.currentURL = discoveredServer.currentURL
            editServer.name = discoveredServer.name

            return editServer.state
        }

        refreshStoredServers()
        Notifications[.didChangeCurrentServerURL].post(newState)

        return newState
    }

    /// server has same id, but (possible) new URL
    @Function(\Action.Cases.addNewURL)
    private func _addNewURL(_ server: ServerState) async throws {
        // Re-query the endpoint instead of trusting discovery-provided identity.
        try await performConnection(server.currentURL.absoluteString, expectedServerID: server.id)
    }

    func retrySavedServer(_ server: ServerState) {
        guard !isRecovering else { return }
        isRecovering = true
        recoveryTask = Task { @MainActor [weak self] in
            let reachable = await ServerAddressRecoveryService.shared.refreshAddressIfNeeded(
                serverID: server.id, currentURL: server.currentURL
            )
            guard !Task.isCancelled, let self else { return }
            self.isRecovering = false
            self.refreshStoredServers()
            if reachable, let updated = self.storedServersByID[server.id] {
                self.events.send(.connected(updated))
            } else {
                self.error = ErrorMessage(L10n.serverSavedUnavailable)
            }
        }
    }

    @Function(\Action.Cases.searchForServers)
    private func _searchForServers() {
        stopSearching()
        localServers.removeAll()
        refreshStoredServers()
        discoveryFailed = false
        guard ServerDiscovery.isEnabled else { return }
        isSearching = true
        let discovery = ServerDiscovery()
        self.discovery = discovery
        // Subscribe synchronously before the first broadcast; weak capture avoids
        // the long-lived async-sequence task retaining the whole view model.
        discoverySubscription = discovery.discoveredServers.sink { [weak self] response in
            guard let self, let server = response.asServerState else { return }
            if let previous = self.localServers.first(where: { $0.id == server.id }) {
                self.localServers.remove(previous)
            }
            self.localServers.append(server)
        }
        failureSubscription = discovery.failures.sink { [weak self] in
            self?.discoveryFailed = true
            self?.stopSearching()
        }
        discovery.broadcast()
        searchTask = Task { @MainActor [weak self] in
            do {
                for _ in 0 ..< 3 {
                    try await Task.sleep(for: .seconds(2))
                    self?.discovery?.broadcast()
                }
                try await Task.sleep(for: .seconds(2))
                self?.stopSearching()
            } catch {}
        }
    }
}
