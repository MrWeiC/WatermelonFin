//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Specific error types for media playback
enum MediaPlayerError: LocalizedError, SystemImageable {

    case networkError(underlying: Error?)
    case codecNotSupported(codec: String?)
    case mediaSourceUnavailable
    case transcodeFailed(reason: String?)
    case authenticationRequired
    case serverUnreachable
    case playerCrashed(player: String)
    case unknown(message: String?)

    var errorDescription: String? {
        switch self {
        case .networkError:
            return L10n.mediaPlayerNetworkConnectionError
        case let .codecNotSupported(codec):
            if let codec {
                return L10n.mediaPlayerUnsupportedFormatWithCodec(codec)
            }
            return L10n.mediaPlayerUnsupportedFormat
        case .mediaSourceUnavailable:
            return L10n.mediaPlayerMediaSourceUnavailable
        case let .transcodeFailed(reason):
            if let reason {
                return L10n.mediaPlayerTranscodingFailedWithReason(reason)
            }
            return L10n.mediaPlayerTranscodingFailed
        case .authenticationRequired:
            return L10n.mediaPlayerAuthenticationRequired
        case .serverUnreachable:
            return L10n.mediaPlayerServerUnreachable
        case let .playerCrashed(player):
            return L10n.mediaPlayerPlayerError(player)
        case let .unknown(message):
            return message ?? L10n.mediaPlayerUnknownPlaybackError
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return L10n.serverConnectionHelp
        case .codecNotSupported:
            return L10n.mediaPlayerCodecRecovery
        case .mediaSourceUnavailable:
            return L10n.mediaPlayerMediaSourceRecovery
        case .transcodeFailed:
            return L10n.mediaPlayerTranscodeRecovery
        case .authenticationRequired:
            return L10n.mediaPlayerAuthenticationRecovery
        case .serverUnreachable:
            return L10n.serverConnectionHelp
        case .playerCrashed:
            return L10n.mediaPlayerCrashRecovery
        case .unknown:
            return L10n.mediaPlayerUnknownRecovery
        }
    }

    var systemImage: String {
        switch self {
        case .networkError: "wifi.exclamationmark"
        case .codecNotSupported: "film.fill"
        case .mediaSourceUnavailable: "xmark.circle"
        case .transcodeFailed: "gearshape.fill"
        case .authenticationRequired: "lock.fill"
        case .serverUnreachable: "server.rack"
        case .playerCrashed: "exclamationmark.triangle"
        case .unknown: "questionmark.circle"
        }
    }

    var secondarySystemImage: String {
        systemImage
    }
}
