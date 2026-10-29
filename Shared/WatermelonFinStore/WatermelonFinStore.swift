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
import Logging

typealias AnyStoredData = WatermelonFinStore.V2.AnyData
typealias ServerModel = WatermelonFinStore.V2.StoredServer
typealias UserModel = WatermelonFinStore.V2.StoredUser

typealias ServerState = WatermelonFinStore.State.Server
typealias UserState = WatermelonFinStore.State.User

// MARK: Namespaces

extension Container {
    var dataStore: Factory<DataStack> {
        self { WatermelonFinStore.dataStack }.singleton
    }
}

enum WatermelonFinStore {

    /// Namespace for V1 objects
    enum V1 {}

    /// Namespace for V2 objects
    enum V2 {}

    /// Namespace for state objects
    enum State {}

    private static let logger = Logger.watermelonfin()
}

// MARK: dataStack

// TODO: cleanup

extension WatermelonFinStore {

    static let dataStack: DataStack = {
        DataStack(
            V1.schema,
            V2.schema,
            migrationChain: ["V1", "V2"]
        )
    }()

    private static let storage: SQLiteStore = {
        SQLiteStore(
            fileName: "WatermelonFin.sqlite",
            migrationMappingProviders: [Mappings.userV1_V2]
        )
    }()

    static func requiresMigration() throws -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingIsolatedStore") { return false }
        #endif
        return try dataStack.requiredMigrationsForStorage(storage).isNotEmpty
    }

    static func setupDataStack() async throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingIsolatedStore") {
            try dataStack.addStorageAndWait(InMemoryStore())
            return
        }
        #endif
        try await withCheckedThrowingContinuation { continuation in
            _ = dataStack.addStorage(storage) { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    logger.error("Failed creating datastack with: \(error.localizedDescription)")
                    continuation.resume(throwing: ErrorMessage(L10n.localStoreCreationFailed(error.localizedDescription)))
                }
            }
        }
    }
}
