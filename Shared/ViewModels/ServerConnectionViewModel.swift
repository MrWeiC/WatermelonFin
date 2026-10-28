//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreStore
import Foundation
import JellyfinAPI

@MainActor
final class ServerConnectionViewModel: ViewModel {

    @Published
    private(set) var server: ServerState

    @Published
    var error: Error?

    @Published
    private(set) var isCheckingAddress = false

    init(server: ServerState) {
        self.server = server
        super.init()
    }

    // TODO: this could probably be cleaner
    @discardableResult
    func delete() -> Bool {

        guard let storedServer = try? dataStack.fetchOne(From<ServerModel>().where(\.$id == server.id)) else {
            logger.critical("Unable to find server to delete")
            return false
        }

        let userStates = storedServer.users.compactMap(\.state)

        // Note: don't use Server/UserState.delete() to have
        //       all deletions in a single transaction
        do {
            try dataStack.perform { transaction in

                // Delete stored data for all users
                for user in storedServer.users {
                    let storedDataClause = AnyStoredData.fetchClause(ownerID: user.id)
                    let storedData = try transaction.fetchAll(storedDataClause)

                    transaction.delete(storedData)
                }

                transaction.delete(storedServer.users)
                transaction.delete(storedServer)
            }

            for user in userStates {
                UserDefaults.userSuite(id: user.id).removeAll()
                user.removeAccessToken()
                keychain.delete("\(user.id)-pin")
            }

            Notifications[.didDeleteServer].post(server)
            return true
        } catch {
            logger.critical("Unable to delete server: \(server.name)")
            return false
        }
    }

    func setCurrentURL(to url: URL) {
        Task { await saveAddress(url, makeCurrent: true) }
    }

    func addAlternateAddress(_ text: String) async {
        do { try await saveAddress(ServerAddressInput.url(from: text), makeCurrent: false) }
        catch { self.error = ErrorMessage("Enter a valid IP address or server URL.") }
    }

    private func saveAddress(_ url: URL, makeCurrent: Bool) async {
        guard !isCheckingAddress else { return }
        isCheckingAddress = true
        defer { isCheckingAddress = false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        let client = JellyfinClient.watermelonfinClient(
            configuration: .watermelonfinConfiguration(url: url),
            sessionConfiguration: configuration
        )
        do {
            let response = try await client.send(Paths.getPublicSystemInfo)
            guard ServerIdentityPolicy.matches(expected: server.id, reported: response.value.id) else {
                throw ErrorMessage("This address belongs to a different Jellyfin server. It was not added.")
            }
            let newState = try dataStack.perform { transaction in
                guard let storedServer = try transaction.fetchOne(From<ServerModel>().where(\.$id == self.server.id)) else {
                    throw ErrorMessage("Unable to find the saved server.")
                }
                storedServer.urls.insert(url)
                if makeCurrent { storedServer.currentURL = url }
                return storedServer.state
            }
            self.server = newState
            if makeCurrent { Notifications[.didChangeCurrentServerURL].post(newState) }
        } catch { self.error = error }
    }
}
