//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Factory
import Foundation
import Logging
import UDPBroadcast

class ServerDiscovery {

    /// Enable only in a future release after Apple's multicast approval,
    /// provisioning updates, and physical-device discovery validation.
    static let isEnabled = false

    private let logger = Logger.watermelonfin()

    private var connection: UDPBroadcastConnection?

    private let failurePublisher = PassthroughSubject<Void, Never>()

    var failures: AnyPublisher<Void, Never> {
        failurePublisher.receive(on: RunLoop.main).eraseToAnyPublisher()
    }

    init() {}

    private func open() throws {
        connection = try UDPBroadcastConnection(
            port: 7359,
            handler: handleServerResponse,
            errorHandler: handleError
        )
    }

    var discoveredServers: AnyPublisher<ServerResponse, Never> {
        discoveredServersPublisher
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    private var discoveredServersPublisher = PassthroughSubject<ServerResponse, Never>()

    func broadcast() {
        guard Self.isEnabled else { return }
        do {
            if connection == nil { try open() }
            try connection?.sendBroadcast("Who is JellyfinServer?")
        } catch {
            failurePublisher.send(())
        }
    }

    func close() {
        connection?.closeConnection()
        connection = nil
        discoveredServersPublisher.send(completion: .finished)
    }

    private func handleServerResponse(_ ipAddress: String, _ port: Int, data: Data) {
        do {
            let response = try JSONDecoder().decode(ServerResponse.self, from: data)
            discoveredServersPublisher.send(response)

            logger.debug("Found local server: \"\(response.name)\" at: \(response.url?.absoluteString ?? "unknown")")
        } catch {
            logger.debug("Unable to decode local server response from: \(ipAddress):\(port)")
        }
    }

    private func handleError(_ error: UDPBroadcastConnection.ConnectionError) {
        failurePublisher.send(())
        logger.debug("Error handling response: \(error.localizedDescription)")
    }
}
