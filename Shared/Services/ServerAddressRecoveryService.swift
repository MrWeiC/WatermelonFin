//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import CoreStore
import Foundation
import JellyfinAPI
import Logging
import Pulse

@MainActor
final class ServerAddressRecoveryService {

    static let shared = ServerAddressRecoveryService()

    private struct VerifiedServer {
        let publicInfo: PublicSystemInfo
        let state: ServerState
    }

    private let logger = Logger.watermelonfin()
    private var recoveryTasks: [String: Task<URL?, Never>] = [:]

    /// Checks the saved address. If it no longer identifies the expected
    /// server, local discovery is attempted.
    @discardableResult
    func refreshAddressIfNeeded(serverID: String, currentURL: URL) async -> Bool {
        if await verify(url: currentURL, expectedServerID: serverID) != nil {
            return true
        }

        return await recover(serverID: serverID, failedURL: currentURL) != nil
    }

    /// Finds another address for a saved server and coalesces simultaneous
    /// failures from the many requests a screen may start in parallel.
    func recover(serverID: String, failedURL: URL) async -> URL? {
        if let recoveryTask = recoveryTasks[serverID] {
            return await recoveryTask.value
        }

        let recoveryTask: Task<URL?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.performRecovery(serverID: serverID, failedURL: failedURL)
        }
        recoveryTasks[serverID] = recoveryTask

        let recoveredURL = await recoveryTask.value
        recoveryTasks[serverID] = nil
        return recoveredURL
    }

    private func performRecovery(serverID: String, failedURL: URL) async -> URL? {
        guard let storedServer = storedServer(id: serverID) else { return nil }

        // Another request may already have recovered and persisted the server.
        if storedServer.currentURL != failedURL {
            return storedServer.currentURL
        }

        let attempt = MatchingServerDiscovery()
        if let discoveredServer = await attempt.find(serverID: serverID),
           let verifiedServer = await verify(
               url: discoveredServer.currentURL,
               expectedServerID: serverID
           )
        {
            if verifiedServer.state.currentURL == storedServer.currentURL {
                return verifiedServer.state.currentURL
            }
            return updateStoredAddress(with: verifiedServer)
        }

        // Discovery can be blocked by network segmentation. Previously known
        // addresses are a useful fallback if DHCP returns to an older lease.
        for savedURL in storedServer.urls where savedURL != failedURL {
            if let verifiedServer = await verify(url: savedURL, expectedServerID: serverID) {
                return updateStoredAddress(with: verifiedServer)
            }
        }

        logger.warning("Unable to recover an address for server \(serverID)")
        return nil
    }

    private func storedServer(id: String) -> ServerState? {
        try? WatermelonFinStore.dataStack
            .fetchOne(From<ServerModel>().where(\.$id == id))?
            .state
    }

    private func verify(url: URL, expectedServerID: String) async -> VerifiedServer? {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 3
        sessionConfiguration.timeoutIntervalForResource = 4

        let client = JellyfinClient.watermelonfinClient(
            configuration: .watermelonfinConfiguration(url: url),
            sessionConfiguration: sessionConfiguration,
            sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.watermelonfin())
        )

        do {
            let response = try await client.send(Paths.getPublicSystemInfo)
            guard response.value.id == expectedServerID else {
                logger.warning("Ignoring address that belongs to a different Jellyfin server")
                return nil
            }

            let connectionURL = Self.processConnectionURL(
                initial: url,
                response: response.response.url
            )
            let server = ServerState(
                urls: [connectionURL],
                currentURL: connectionURL,
                name: response.value.serverName ?? expectedServerID,
                id: expectedServerID,
                usersIDs: []
            )

            return VerifiedServer(publicInfo: response.value, state: server)
        } catch {
            return nil
        }
    }

    private func updateStoredAddress(with verifiedServer: VerifiedServer) -> URL? {
        let discoveredServer = verifiedServer.state

        do {
            let newState = try WatermelonFinStore.dataStack.perform { transaction in
                guard let editServer = try transaction.fetchOne(
                    From<ServerModel>().where(\.$id == discoveredServer.id)
                ) else {
                    throw ErrorMessage("Unable to find the saved Jellyfin server")
                }

                editServer.urls.insert(discoveredServer.currentURL)
                editServer.currentURL = discoveredServer.currentURL
                editServer.name = discoveredServer.name
                return editServer.state
            }

            StoredValues[.Server.publicInfo(id: newState.id)] = verifiedServer.publicInfo
            logger.info("Recovered server \(newState.id) at \(newState.currentURL.absoluteString)")
            Notifications[.didChangeCurrentServerURL].post(newState)
            return newState.currentURL
        } catch {
            logger.error("Unable to save recovered server address: \(error.localizedDescription)")
            return nil
        }
    }

    private static func processConnectionURL(initial: URL, response: URL?) -> URL {
        guard let response else { return initial }

        let newURL = response.absoluteString.trimmingSuffix(
            Paths.getPublicSystemInfo.url?.absoluteString ?? ""
        )
        return URL(string: newURL) ?? initial
    }
}

@MainActor
private final class MatchingServerDiscovery {

    private let discovery = ServerDiscovery()
    private var cancellable: AnyCancellable?
    private var continuation: CheckedContinuation<ServerState?, Never>?
    private var timeoutTask: Task<Void, Never>?

    func find(serverID: String) async -> ServerState? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                cancellable = discovery.discoveredServers
                    .filter { $0.id == serverID }
                    .compactMap(\.asServerState)
                    .first()
                    .sink { [weak self] server in
                        self?.finish(with: server)
                    }

                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(1.5))
                        self?.discovery.broadcast()
                        try await Task.sleep(for: .seconds(2.5))
                    } catch {
                        return
                    }
                    self?.finish(with: nil)
                }

                discovery.broadcast()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    private func finish(with server: ServerState?) {
        guard let continuation else { return }

        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        cancellable?.cancel()
        cancellable = nil
        discovery.close()
        continuation.resume(returning: server)
    }
}
