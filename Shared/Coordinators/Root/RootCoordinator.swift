//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import Get
import Logging
import SwiftUI

@MainActor
final class RootCoordinator: ObservableObject {

    @Published
    var root: RootItem = .appLoading

    private let logger = Logger.watermelonfin()

    init() {
        Task {
            do {
                try await WatermelonFinStore.setupDataStack()

                if Container.shared.currentUserSession() != nil, !Defaults[.signOutOnClose] {
                    var isServerReachable = false

                    if let session = Container.shared.currentUserSession() {
                        // Resolve a stale DHCP address before constructing the
                        // main UI. Otherwise its first requests race recovery
                        // and fail against the old address.
                        isServerReachable = await ServerAddressRecoveryService.shared.refreshAddressIfNeeded(
                            serverID: session.server.id,
                            currentURL: session.server.currentURL
                        )
                    }

                    // Recovery may have replaced the cached session with one
                    // targeting the new address. Validate the saved token on
                    // that refreshed session before showing authenticated UI.
                    if isServerReachable,
                       let refreshedSession = Container.shared.currentUserSession(),
                       await validateSavedSession(refreshedSession) == false
                    {
                        return
                    }

                    #if os(tvOS)
                    await MainActor.run {
                        root(.mainTab)
                    }
                    #else
                    await MainActor.run {
                        root(.serverCheck)
                    }
                    #endif
                } else {
                    #if os(tvOS)
                    TopShelfCache.clear()
                    #endif

                    await MainActor.run {
                        root(.selectUser)
                    }
                }

            } catch {
                await MainActor.run {
                    Notifications[.didFailMigration].post()
                }
            }
        }

        // Notification setup for state
        Notifications[.didSignIn].subscribe(self, selector: #selector(didSignIn))
        Notifications[.didSignOut].subscribe(self, selector: #selector(didSignOut))
        Notifications[.didChangeCurrentServerURL].subscribe(self, selector: #selector(didChangeCurrentServerURL(_:)))
        Notifications[.didDeleteServer].subscribe(self, selector: #selector(didDeleteServer(_:)))
    }

    func root(_ newRoot: RootItem) {
        root = newRoot
    }

    @objc
    private func didSignIn() {
        logger.info("Signed in")

        guard Container.shared.currentUserSession() != nil else {
            root(.selectUser)
            return
        }

        #if os(tvOS)
        root(.mainTab)
        #else
        root(.serverCheck)
        #endif
    }

    @objc
    private func didSignOut() {
        logger.info("Signed out")

        #if os(tvOS)
        TopShelfCache.clear()
        #endif

        root(.selectUser)
    }

    @objc
    func didChangeCurrentServerURL(_ notification: Notification) {

        guard Container.shared.currentUserSession() != nil else { return }

        Container.shared.currentUserSession.reset()

        // Startup owns the transition out of appLoading so it can validate
        // the saved token before authenticated views are constructed.
        guard root.id != RootItem.appLoading.id else { return }

        Notifications[.didSignIn].post()
    }

    @objc
    private func didDeleteServer(_ notification: Notification) {
        guard let deletedServer = notification.userInfo?["payload"] as? ServerState,
              Container.shared.currentUserSession()?.server.id == deletedServer.id
        else {
            return
        }

        Defaults[.lastSignedInUserID] = .signedOut
        Container.shared.currentUserSession.reset()
        Notifications[.didSignOut].post()
    }

    private func validateSavedSession(_ session: UserSession) async -> Bool {
        do {
            _ = try await session.user.getUserData(server: session.server)
            return true
        } catch APIError.unacceptableStatusCode(401) {
            logger.warning("Saved Jellyfin access token is no longer valid")
            session.user.removeAccessToken()
            Defaults[.lastSignedInUserID] = .signedOut
            Container.shared.currentUserSession.reset()
            Notifications[.didSignOut].post()
            return false
        } catch {
            // Reachability was already verified. Let individual screens
            // surface non-authentication API errors with their normal retry UI.
            logger.warning("Unable to validate saved Jellyfin session: \(error.localizedDescription)")
            return true
        }
    }
}
