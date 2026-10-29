//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI

final class WatermelonFinAPIClientDelegate: APIClientDelegate {

    typealias AddressRecovery = (_ serverID: String, _ failedURL: URL) async -> URL?

    weak var jellyfinClient: JellyfinClient?

    private let actualDelegate: APIClientDelegate?
    private let addressRecovery: AddressRecovery
    private let configuredServerURL: URL?
    private let recoveredURLLock = NSLock()
    private let serverID: String?
    private var _recoveredServerURL: URL?
    private var retargetSourceURLs: Set<URL> = []

    init(
        actualDelegate: APIClientDelegate? = nil,
        serverID: String? = nil,
        serverURL: URL? = nil,
        addressRecovery: @escaping AddressRecovery = { serverID, failedURL in
            await ServerAddressRecoveryService.shared.recover(
                serverID: serverID,
                failedURL: failedURL
            )
        }
    ) {
        self.actualDelegate = actualDelegate
        self.addressRecovery = addressRecovery
        self.configuredServerURL = serverURL
        self.serverID = serverID
    }

    func client(_ client: APIClient, willSendRequest request: inout URLRequest) async throws {
        // The pinned SDK's QuickConnect helper still uses deprecated GET.
        // Current Jellyfin servers require POST; preserve reverse-proxy prefixes.
        if request.httpMethod == "GET",
           request.url?.path.lowercased().hasSuffix("/quickconnect/initiate") == true
        {
            request.httpMethod = "POST"
        }
        if let requestURL = request.url {
            let recoveryState = recoveredServerState
            if let recoveredServerURL = recoveryState.url {
                let sourceURLs = [configuredServerURL].compactMap(\.self) + recoveryState.sourceURLs

                for sourceURL in sourceURLs {
                    if let retargetedURL = Self.retarget(
                        requestURL,
                        from: sourceURL,
                        to: recoveredServerURL
                    ) {
                        request.url = retargetedURL
                        break
                    }
                }
            }
        }

        if let configuration = jellyfinClient?.configuration {
            request.setValue(
                Self.authorizationHeader(configuration: configuration),
                forHTTPHeaderField: "Authorization"
            )
        }

        try await actualDelegate?.client(client, willSendRequest: &request)
    }

    func client(_ client: APIClient, validateResponse response: HTTPURLResponse, data: Data, task: URLSessionTask) throws {
        if let actualDelegate {
            try actualDelegate.client(client, validateResponse: response, data: data, task: task)
        } else {
            guard (200 ..< 300).contains(response.statusCode) else {
                throw APIError.unacceptableStatusCode(response.statusCode)
            }
        }
    }

    func client(_ client: APIClient, shouldRetry task: URLSessionTask, error: Error, attempts: Int) async throws -> Bool {
        if try await actualDelegate?.client(client, shouldRetry: task, error: error, attempts: attempts) == true {
            return true
        }

        guard attempts == 1,
              NetworkError.from(error).canRecoverServerAddress,
              let serverID,
              let failedURL = recoveredServerURL ?? configuredServerURL,
              let newURL = await addressRecovery(serverID, failedURL)
        else {
            return false
        }

        setRecoveredServerURL(newURL)
        return true
    }

    func client(_ client: APIClient, makeURLForRequest request: Request<some Any>) throws -> URL? {
        try actualDelegate?.client(client, makeURLForRequest: request)
    }

    static func authorizationHeader(configuration: JellyfinClient.Configuration) -> String {
        var fields: [(key: String, value: String)] = [
            ("Client", configuration.client),
            ("Device", configuration.deviceName),
            ("DeviceId", configuration.deviceID),
            ("Version", configuration.version),
        ]

        if let accessToken = configuration.accessToken {
            fields.append(("Token", accessToken))
        }

        let parameters = fields
            .map { "\($0.key)=\(quoted($0.value))" }
            .joined(separator: ", ")

        return "MediaBrowser \(parameters)"
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return "\"\(escaped)\""
    }

    private var recoveredServerURL: URL? {
        recoveredURLLock.lock()
        defer { recoveredURLLock.unlock() }
        return _recoveredServerURL
    }

    private var recoveredServerState: (url: URL?, sourceURLs: [URL]) {
        recoveredURLLock.lock()
        defer { recoveredURLLock.unlock() }
        return (_recoveredServerURL, Array(retargetSourceURLs))
    }

    private func setRecoveredServerURL(_ url: URL) {
        recoveredURLLock.lock()
        if let currentURL = _recoveredServerURL ?? configuredServerURL {
            retargetSourceURLs.insert(currentURL)
        }
        _recoveredServerURL = url
        recoveredURLLock.unlock()
    }

    private static func retarget(_ requestURL: URL, from oldBaseURL: URL, to newBaseURL: URL) -> URL? {
        guard let request = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              let oldBase = URLComponents(url: oldBaseURL, resolvingAgainstBaseURL: false),
              let newBase = URLComponents(url: newBaseURL, resolvingAgainstBaseURL: false),
              request.scheme == oldBase.scheme,
              request.host == oldBase.host,
              request.port == oldBase.port
        else {
            return nil
        }

        let oldPath = oldBase.percentEncodedPath.trimmingSuffix("/")
        let requestPath = request.percentEncodedPath
        guard oldPath.isEmpty || requestPath == oldPath || requestPath.hasPrefix("\(oldPath)/") else {
            return nil
        }

        let suffix = oldPath.isEmpty ? requestPath : String(requestPath.dropFirst(oldPath.count))
        let newPath = newBase.percentEncodedPath.trimmingSuffix("/")

        var result = request
        result.scheme = newBase.scheme
        result.user = newBase.user
        result.password = newBase.password
        result.host = newBase.host
        result.port = newBase.port
        result.percentEncodedPath = newPath + suffix
        return result.url
    }
}

extension JellyfinClient {

    static func watermelonfinClient(
        configuration: Configuration,
        delegate actualDelegate: APIClientDelegate? = nil,
        serverID: String? = nil,
        sessionConfiguration: URLSessionConfiguration = .default,
        sessionDelegate: URLSessionDelegate? = nil
    ) -> JellyfinClient {
        let delegate = WatermelonFinAPIClientDelegate(
            actualDelegate: actualDelegate,
            serverID: serverID,
            serverURL: configuration.url
        )
        let client = JellyfinClient(
            configuration: configuration,
            delegate: delegate,
            sessionConfiguration: sessionConfiguration,
            sessionDelegate: sessionDelegate
        )

        delegate.jellyfinClient = client

        return client
    }
}
