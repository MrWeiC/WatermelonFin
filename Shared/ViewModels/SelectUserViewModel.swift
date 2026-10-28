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
import Get
import JellyfinAPI
import KeychainSwift
import OrderedCollections

@MainActor
@Stateful
final class SelectUserViewModel: ViewModel {

    @CasePathable
    enum Action {
        case deleteUsers(Set<UserState>)
        case error
        case getServers
        case signIn(UserState, server: ServerState, pin: String)
    }

    enum Event {
        case discoverServers
        case error
        case expiredSession(UserState, ServerState)
        case signedIn(UserState)
    }

    @Published
    private(set) var servers: OrderedDictionary<ServerState, [UserState]> = [:]

    @Function(\Action.Cases.deleteUsers)
    private func _deleteUsers(_ users: Set<UserState>) async throws {
        for user in users {
            try user.delete()
        }

        try await _getServers()
    }

    @Function(\Action.Cases.getServers)
    private func _getServers() async throws {
        let newServers = try WatermelonFinStore
            .dataStack
            .fetchAll(From<ServerModel>())
            .map(\.state)
            .sorted(using: \.name)
            .zipped(map: getUsers)
            .reduce(into: OrderedDictionary<ServerState, [UserState]>()) { partialResult, pair in
                partialResult[pair.0] = pair.1
            }

        servers = newServers
        // Loading account state must never present UI over the launch animation.
        // Discovery is entered through Add Server or an explicit failed sign-in.
    }

    private func getUsers(for server: ServerState) throws -> [UserState] {
        guard let storedServer = try? dataStack.fetchOne(From<ServerModel>().where(\.$id == server.id)) else {
            logger.critical(
                "Unable to find server for users",
                metadata: [
                    "serverName": .string(server.name),
                ]
            )
            throw ErrorMessage(L10n.unknownError)
        }

        return storedServer.users
            .compactMap(\.state)
    }

    @Function(\Action.Cases.signIn)
    private func _signIn(_ user: UserState, _ server: ServerState, _ pin: String) async throws {
        if user.accessPolicy == .requirePin {
            guard LocalPINPolicy.isValid(pin), let storedPin = keychain.get("\(user.id)-pin"), pin == storedPin else {
                throw ErrorMessage(L10n.incorrectPinForUser(user.username))
            }
        }

        guard await ServerAddressRecoveryService.shared.refreshAddressIfNeeded(
            serverID: server.id, currentURL: server.currentURL
        ), let refreshedServer = try? dataStack.fetchOne(From<ServerModel>().where(\.$id == server.id))?.state else {
            events.send(.discoverServers)
            return
        }
        guard user.hasAccessToken else {
            events.send(.expiredSession(user, refreshedServer))
            return
        }
        do {
            _ = try await user.getUserData(server: refreshedServer)
        } catch {
            if error.isUnauthorizedResponse {
                user.removeAccessToken()
                events.send(.expiredSession(user, refreshedServer))
                return
            }

            throw error
        }

        events.send(.signedIn(user))
    }
}

private extension Error {

    var isUnauthorizedResponse: Bool {
        guard let apiError = self as? APIError,
              case APIError.unacceptableStatusCode(401) = apiError
        else {
            return false
        }

        return true
    }
}
