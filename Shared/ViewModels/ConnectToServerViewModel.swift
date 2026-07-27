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

    /// no longer-found servers are not cleared, but not an issue
    @Published
    var localServers: OrderedSet<ServerState> = []

    @Published
    private(set) var storedServersByID: [String: ServerState] = [:]

    private let discovery = ServerDiscovery()
    private var discoveryTask: Task<Void, Never>?

    deinit {
        discoveryTask?.cancel()
        discovery.close()
    }

    override init() {
        super.init()

        Task { @MainActor [weak self] in
            self?.refreshStoredServers()
        }

        discoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for await response in self.discovery.discoveredServers.values {
                if let serverState = response.asServerState {
                    if let previousAddress = self.localServers.first(where: { $0.id == serverState.id }) {
                        self.localServers.remove(previousAddress)
                    }
                    self.localServers.append(serverState)
                }
            }
        }
    }

    @Function(\Action.Cases.connect)
    private func connectToServer(_ url: String) async throws {

        let formattedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .objectReplacement)
            .trimmingCharacters(in: ["/"])
            .prepending("http://", if: !url.contains("://"))

        guard let url = URL(string: formattedURL) else { throw ErrorMessage("Invalid URL") }

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
            sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.watermelonfin())
        )

        let response = try await client.send(Paths.getPublicSystemInfo)

        guard let name = response.value.serverName,
              let id = response.value.id
        else {
            logger.critical("Missing server data from network call")
            throw ErrorMessage(L10n.unknownError)
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
                throw ErrorMessage("An internal error has occurred")
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
    private func _addNewURL(_ server: ServerState) throws {
        let existingServer = existingServer(for: server) ?? server
        let newState = try updateStoredAddress(for: existingServer, discoveredServer: server)
        events.send(.connected(newState))
    }

    @Function(\Action.Cases.searchForServers)
    private func _searchForServers() {
        discovery.broadcast()
    }
}
