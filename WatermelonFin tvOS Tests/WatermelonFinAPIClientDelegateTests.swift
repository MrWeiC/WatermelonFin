//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Factory
import Get
import JellyfinAPI
import KeychainSwift
@testable import WatermelonFin_tvOS
import XCTest

@MainActor
final class WatermelonFinAPIClientDelegateTests: XCTestCase {

    func testAuthorizationHeaderQuotesValuesWithSpaces() throws {
        let configuration = try JellyfinClient.Configuration(
            url: XCTUnwrap(URL(string: "http://jellyfin.local:8096")),
            accessToken: "token with spaces",
            client: "WatermelonFin Apple TV",
            deviceName: "Living Room",
            deviceID: "tvOS_ABC123",
            version: "1.0"
        )

        let header = WatermelonFinAPIClientDelegate.authorizationHeader(configuration: configuration)

        XCTAssertEqual(
            header,
            #"MediaBrowser Client="WatermelonFin Apple TV", Device="Living Room", DeviceId="tvOS_ABC123", Version="1.0", Token="token with spaces""#
        )
    }

    func testAuthorizationHeaderOmitsMissingToken() throws {
        let configuration = try JellyfinClient.Configuration(
            url: XCTUnwrap(URL(string: "http://jellyfin.local:8096")),
            client: "WatermelonFin Apple TV",
            deviceName: "Living Room",
            deviceID: "tvOS_ABC123",
            version: "1.0"
        )

        let header = WatermelonFinAPIClientDelegate.authorizationHeader(configuration: configuration)

        XCTAssertFalse(header.contains("Token="))
    }

    func testConnectionFailureRecoversAndRetargetsRetry() async throws {
        let oldURL = try XCTUnwrap(URL(string: "http://192.0.2.10:8096/jellyfin"))
        let newURL = try XCTUnwrap(URL(string: "http://192.0.2.11:8096/jellyfin"))
        let requestURL = try XCTUnwrap(URL(string: "http://192.0.2.10:8096/jellyfin/Users/user/Items?limit=20"))
        var recoveredServerID: String?
        var recoveredFailedURL: URL?

        let delegate = WatermelonFinAPIClientDelegate(
            serverID: "stable-server-id",
            serverURL: oldURL
        ) { serverID, failedURL in
            recoveredServerID = serverID
            recoveredFailedURL = failedURL
            return newURL
        }
        let client = APIClient(baseURL: oldURL)
        let task = URLSession.shared.dataTask(with: requestURL)
        defer { task.cancel() }

        let shouldRetry = try await delegate.client(
            client,
            shouldRetry: task,
            error: URLError(.cannotConnectToHost),
            attempts: 1
        )

        XCTAssertTrue(shouldRetry)
        XCTAssertEqual(recoveredServerID, "stable-server-id")
        XCTAssertEqual(recoveredFailedURL, oldURL)

        var retryRequest = URLRequest(url: requestURL)
        try await delegate.client(client, willSendRequest: &retryRequest)
        XCTAssertEqual(
            retryRequest.url,
            URL(string: "http://192.0.2.11:8096/jellyfin/Users/user/Items?limit=20")
        )
    }

    func testRecoveredRequestRetainsAccessToken() async throws {
        let oldURL = try XCTUnwrap(URL(string: "http://192.0.2.10:8096"))
        let newURL = try XCTUnwrap(URL(string: "http://192.0.2.11:8096"))
        let requestURL = oldURL.appendingPathComponent("Users/Me")
        let configuration = try JellyfinClient.Configuration(
            url: oldURL,
            accessToken: "saved-user-token",
            client: "WatermelonFin Apple TV",
            deviceName: "Living Room",
            deviceID: "tvOS_ABC123",
            version: "1.0"
        )
        let delegate = WatermelonFinAPIClientDelegate(
            serverID: "stable-server-id",
            serverURL: oldURL
        ) { _, _ in
            newURL
        }
        let jellyfinClient = JellyfinClient(configuration: configuration)
        delegate.jellyfinClient = jellyfinClient
        let client = APIClient(baseURL: oldURL)
        let task = URLSession.shared.dataTask(with: requestURL)
        defer { task.cancel() }

        let shouldRetry = try await delegate.client(
            client,
            shouldRetry: task,
            error: URLError(.cannotConnectToHost),
            attempts: 1
        )
        XCTAssertTrue(shouldRetry)

        var retryRequest = URLRequest(url: requestURL)
        try await delegate.client(client, willSendRequest: &retryRequest)

        XCTAssertEqual(retryRequest.url, newURL.appendingPathComponent("Users/Me"))
        XCTAssertEqual(
            retryRequest.value(forHTTPHeaderField: "Authorization"),
            #"MediaBrowser Client="WatermelonFin Apple TV", Device="Living Room", DeviceId="tvOS_ABC123", Version="1.0", Token="saved-user-token""#
        )
    }

    func testNonConnectionFailureDoesNotAttemptAddressRecovery() async throws {
        let serverURL = try XCTUnwrap(URL(string: "http://192.0.2.10:8096"))
        var didAttemptRecovery = false
        let delegate = WatermelonFinAPIClientDelegate(
            serverID: "stable-server-id",
            serverURL: serverURL
        ) { _, _ in
            didAttemptRecovery = true
            return nil
        }
        let client = APIClient(baseURL: serverURL)
        let task = URLSession.shared.dataTask(with: serverURL)
        defer { task.cancel() }

        let shouldRetry = try await delegate.client(
            client,
            shouldRetry: task,
            error: URLError(.secureConnectionFailed),
            attempts: 1
        )

        XCTAssertFalse(shouldRetry)
        XCTAssertFalse(didAttemptRecovery)
    }

    func testRecoveredSameAddressStillRetriesTransientFailureOnce() async throws {
        let serverURL = try XCTUnwrap(URL(string: "http://192.0.2.10:8096"))
        let delegate = WatermelonFinAPIClientDelegate(
            serverID: "stable-server-id",
            serverURL: serverURL
        ) { _, _ in
            serverURL
        }
        let client = APIClient(baseURL: serverURL)
        let task = URLSession.shared.dataTask(with: serverURL)
        defer { task.cancel() }

        let shouldRetry = try await delegate.client(
            client,
            shouldRetry: task,
            error: URLError(.networkConnectionLost),
            attempts: 1
        )

        XCTAssertTrue(shouldRetry)
    }

    func testLaterAddressChangeRetargetsRequestFromPreviouslyRecoveredURL() async throws {
        let originalURL = try XCTUnwrap(URL(string: "http://192.0.2.10:8096"))
        let secondURL = try XCTUnwrap(URL(string: "http://192.0.2.11:8096"))
        let thirdURL = try XCTUnwrap(URL(string: "http://192.0.2.12:8096"))
        var recoveredURLs = [secondURL, thirdURL]
        let delegate = WatermelonFinAPIClientDelegate(
            serverID: "stable-server-id",
            serverURL: originalURL
        ) { _, _ in
            recoveredURLs.removeFirst()
        }
        let client = APIClient(baseURL: originalURL)

        for failedBaseURL in [originalURL, secondURL] {
            let failedRequestURL = failedBaseURL.appendingPathComponent("Users/user/Items")
            let task = URLSession.shared.dataTask(with: failedRequestURL)
            defer { task.cancel() }

            let shouldRetry = try await delegate.client(
                client,
                shouldRetry: task,
                error: URLError(.cannotConnectToHost),
                attempts: 1
            )
            XCTAssertTrue(shouldRetry)
        }

        var retryRequest = URLRequest(url: secondURL.appendingPathComponent("Users/user/Items"))
        try await delegate.client(client, willSendRequest: &retryRequest)
        XCTAssertEqual(
            retryRequest.url,
            thirdURL.appendingPathComponent("Users/user/Items")
        )
    }

    func testUserStateHasAccessTokenIsFalseWhenKeychainEntryIsMissing() {
        let user = UserState(
            id: "missing-token-user",
            serverID: "server",
            username: "Local User"
        )

        Container.shared.keychainService().delete("\(user.id)-accessToken")

        XCTAssertFalse(user.hasAccessToken)
    }

    func testDefaultLocalizationUsesSimplifiedChinese() {
        XCTAssertEqual(L10n.connect, "连接")
        XCTAssertEqual(L10n.addUser, "添加已有用户")
    }

    func testSaveExistingRefreshesMissingAccessTokenEvenWithoutReplace() async throws {
        let user = UserState(
            id: "existing-user-missing-token",
            serverID: "server",
            username: "Local User"
        )
        let accessTokenKey = "\(user.id)-accessToken"
        let newAccessToken = "new-token"
        Container.shared.keychainService().delete(accessTokenKey)

        let serverURL = try XCTUnwrap(URL(string: "http://jellyfin.local:8096"))
        let viewModel = UserSignInViewModel(
            server: ServerState(
                urls: [serverURL],
                currentURL: serverURL,
                name: "Jellyfin",
                id: "server",
                usersIDs: [user.id]
            )
        )

        let saved = expectation(description: "existing user saved")
        var cancellables = Set<AnyCancellable>()
        viewModel.events
            .sink { event in
                if case .saved = event {
                    saved.fulfill()
                }
            }
            .store(in: &cancellables)

        await viewModel.saveExisting(
            user: ((user, newAccessToken), UserDto()),
            replaceForAccessToken: false,
            authenticationAction: (
                LocalUserAuthenticationAction { _, _ in EmptyEvaluatedUserAccessPolicy() },
                .none,
                nil
            ),
            evaluatedPolicyMap: .init { $0 }
        )

        await fulfillment(of: [saved], timeout: 1)
        XCTAssertEqual(Container.shared.keychainService().get(accessTokenKey), newAccessToken)

        Container.shared.keychainService().delete(accessTokenKey)
        _ = cancellables
    }

    func testFailedKeychainWriteDoesNotReportExistingUserAsSaved() async throws {
        Container.shared.keychainService.register { FailingKeychain() }
        defer { Container.shared.keychainService.reset() }

        let user = UserState(
            id: "existing-user-keychain-failure",
            serverID: "server",
            username: "Local User"
        )
        let serverURL = try XCTUnwrap(URL(string: "http://jellyfin.local:8096"))
        let viewModel = UserSignInViewModel(
            server: ServerState(
                urls: [serverURL],
                currentURL: serverURL,
                name: "Jellyfin",
                id: "server",
                usersIDs: [user.id]
            )
        )

        let saved = expectation(description: "existing user must not be reported as saved")
        saved.isInverted = true
        var cancellables = Set<AnyCancellable>()
        viewModel.events
            .sink { event in
                if case .saved = event {
                    saved.fulfill()
                }
            }
            .store(in: &cancellables)

        await viewModel.saveExisting(
            user: ((user, "new-token"), UserDto()),
            replaceForAccessToken: true,
            authenticationAction: (
                LocalUserAuthenticationAction { _, _ in EmptyEvaluatedUserAccessPolicy() },
                .none,
                nil
            ),
            evaluatedPolicyMap: .init { $0 }
        )

        await fulfillment(of: [saved], timeout: 0.2)
        XCTAssertNotNil(viewModel.error)
        _ = cancellables
    }
}

private final class FailingKeychain: KeychainSwift {

    override func set(
        _ value: String,
        forKey key: String,
        withAccess access: KeychainSwiftAccessOptions? = nil
    ) -> Bool {
        false
    }
}
