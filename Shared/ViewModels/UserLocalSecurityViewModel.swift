//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import KeychainSwift

final class UserLocalSecurityViewModel: ViewModel, Eventful {

    enum Event: Hashable {
        case error(ErrorMessage)
        case promptForOldDeviceAuth
        case promptForOldPin
        case promptForNewDeviceAuth
        case promptForNewPin
    }

    var events: AnyPublisher<Event, Never> {
        eventSubject
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    private var eventSubject: PassthroughSubject<Event, Never> = .init()

    /// Will throw and send event if needing to prompt for old auth.
    func checkForOldPolicy() throws {

        let oldPolicy = try requireSession().user.accessPolicy

        switch oldPolicy {
        case .requireDeviceAuthentication:
            eventSubject.send(.promptForOldDeviceAuth)

            throw ErrorMessage("Prompt for old device auth")
        case .requirePin:
            eventSubject.send(.promptForOldPin)

            throw ErrorMessage("Prompt for old pin")
        case .none: ()
        }
    }

    /// Will throw and send event if needing to prompt for new auth.
    func checkFor(newPolicy: UserAccessPolicy) throws {
        switch newPolicy {
        case .requireDeviceAuthentication:
            eventSubject.send(.promptForNewDeviceAuth)
            throw ErrorMessage("Prompt for new device auth")
        case .requirePin:
            eventSubject.send(.promptForNewPin)
            throw ErrorMessage("Prompt for new pin")
        case .none: ()
        }
    }

    func check(oldPin: String) throws {

        let session = try requireSession()
        guard let storedPin = keychain.get("\(session.user.id)-pin"),
              LocalPINPolicy.isValid(oldPin), oldPin == storedPin
        else {
            let error = ErrorMessage(L10n.incorrectPinForUser(session.user.username))
            eventSubject.send(.error(error))
            throw error
        }
    }

    func set(newPolicy: UserAccessPolicy, newPin: String, newPinHint: String) throws {
        let session = try requireSession()
        if newPolicy == .requirePin, !LocalPINPolicy.isValid(newPin) {
            throw ErrorMessage(L10n.requirePinDescription)
        }

        if newPolicy == .requirePin {
            try session.user.storePin(newPin)
        } else {
            keychain.delete("\(session.user.id)-pin")
        }

        session.user.accessPolicy = newPolicy
        session.user.pinHint = newPinHint
    }
}
