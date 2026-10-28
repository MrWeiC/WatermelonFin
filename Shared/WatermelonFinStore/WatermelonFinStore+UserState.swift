//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreStore
import Factory
import Foundation
import JellyfinAPI
import KeychainSwift
import Logging
import Pulse
import UIKit

private let logger = Logger.watermelonfin()

// Note: it is kind of backwards to have a "state" object with a mix of
//       non-mutable and "mutable" values, but it just works.

extension WatermelonFinStore.State {

    struct User: Hashable, Identifiable {

        let id: String
        let serverID: String
        let username: String

        init(
            id: String,
            serverID: String,
            username: String
        ) {
            self.id = id
            self.serverID = serverID
            self.username = username
        }
    }
}

extension UserState {

    typealias Key = StoredValues.Key

    var hasAccessToken: Bool {
        guard let accessToken = Container.shared.keychainService().get("\(id)-accessToken") else {
            return false
        }

        return accessToken.isNotEmpty
    }

    var accessToken: String {
        guard let accessToken = Container.shared.keychainService().get("\(id)-accessToken") else {
            logger.error("access token missing in keychain for user \(id)")
            return ""
        }

        return accessToken
    }

    func storeAccessToken(_ accessToken: String) throws {
        guard Container.shared.keychainService().set(
            accessToken,
            forKey: "\(id)-accessToken",
            withAccess: .accessibleWhenUnlockedThisDeviceOnly
        ) else {
            logger.error("Unable to save access token in keychain for user \(id)")
            throw ErrorMessage("\(L10n.save): \(L10n.failed)")
        }
    }

    func removeAccessToken() {
        Container.shared.keychainService().delete("\(id)-accessToken")
    }

    var data: UserDto {
        get {
            StoredValues[.User.data(id: id)]
        }
        nonmutating set {
            StoredValues[.User.data(id: id)] = newValue
        }
    }

    var permissions: UserPermissions {
        UserPermissions(data.policy)
    }

    var pin: String {
        guard let pin = Container.shared.keychainService().get("\(id)-pin") else {
            logger.error("pin missing in keychain for user \(id)")
            return ""
        }

        return pin
    }

    func storePin(_ pin: String) throws {
        guard Container.shared.keychainService().set(
            pin,
            forKey: "\(id)-pin",
            withAccess: .accessibleWhenUnlockedThisDeviceOnly
        ) else {
            logger.error("Unable to save PIN in keychain for user \(id)")
            throw ErrorMessage("\(L10n.save): \(L10n.failed)")
        }
    }

    var pinHint: String {
        get {
            StoredValues[.User.pinHint(id: id)]
        }
        nonmutating set {
            StoredValues[.User.pinHint(id: id)] = newValue
        }
    }

    var accessPolicy: UserAccessPolicy {
        get {
            StoredValues[.User.accessPolicy(id: id)]
        }
        nonmutating set {
            StoredValues[.User.accessPolicy(id: id)] = newValue
        }
    }
}

extension UserState {

    /// Deletes the model that this state represents and
    /// all settings from `Defaults` `Keychain`, and `StoredValues`
    func delete() throws {
        try WatermelonFinStore.dataStack.perform { transaction in
            guard let storedUser = try transaction.fetchOne(From<UserModel>().where(\.$id == id)) else {
                throw ErrorMessage(L10n.userToDeleteNotFound)
            }

            let storedDataClause = AnyStoredData.fetchClause(ownerID: id)
            let storedData = try transaction.fetchAll(storedDataClause)

            transaction.delete(storedUser)
            transaction.delete(storedData)
        }

        UserDefaults.userSuite(id: id).removeAll()

        let keychain = Container.shared.keychainService()
        keychain.delete("\(id)-pin")
        keychain.delete("\(id)-accessToken")
    }

    /// Deletes user settings from `UserDefaults` and `StoredValues`
    ///
    /// Note: if performing deletion with another transaction, use
    ///       `AnyStoredData.fetchClause` instead within that transaction
    ///       and delete `Defaults` manually
    func deleteSettings() throws {
        try WatermelonFinStore.dataStack.perform { transaction in
            let userData = try transaction.fetchAll(
                From<AnyStoredData>()
                    .where(combineByAnd: Where(\.$ownerID == id), Where("%K BEGINSWITH %@", "domain", "setting"))
            )

            transaction.delete(userData)
        }

        UserDefaults.userSuite(id: id).removeAll()
    }

    /// Must pass the server to create a JellyfinClient
    /// with an access token
    func getUserData(server: ServerState) async throws -> UserDto {
        let client = JellyfinClient.watermelonfinClient(
            configuration: .watermelonfinConfiguration(
                url: server.currentURL,
                accessToken: accessToken
            ),
            serverID: server.id,
            sessionConfiguration: .watermelonfin,
            sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.watermelonfin())
        )

        let request = Paths.getCurrentUser
        let response = try await client.send(request)

        return response.value
    }

    /// we will always crop to a square, so just use width
    func profileImageSource(
        client: JellyfinClient
    ) -> ImageSource {
        let parameters = Paths.GetUserImageParameters(
            userID: id
        )
        let request = Paths.getUserImage(parameters: parameters)

        let profileImageURL = client.fullURL(with: request)

        return ImageSource(url: profileImageURL)
    }
}
