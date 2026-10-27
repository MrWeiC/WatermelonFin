//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import SwiftUI

struct SettingsView: View {
    @Router
    private var router
    @StateObject
    private var viewModel = SettingsViewModel()
    @Default(.userAppearance)
    private var appearance
    @Default(.userAccentColor)
    private var accent
    @Default(.VideoPlayer.videoPlayerType)
    private var playerType

    var body: some View {
        Form {
            Section(L10n.accountAndServer) {
                if let session = viewModel.userSession {
                    LabeledContent(L10n.user, value: session.user.username)
                    Button(session.server.name) { router.route(to: .editServer(server: session.server)) }
                    Button(L10n.profile) { router.route(to: .userProfile(viewModel: viewModel)) }
                }
                Button(L10n.switchUser, systemImage: "person.2") {
                    Defaults[.lastSignedInUserID] = .signedOut
                    Container.shared.currentUserSession.reset()
                    Notifications[.didSignOut].post()
                }
            }
            Section(L10n.playback) {
                Picker(L10n.videoPlayerType, selection: $playerType)
                Button(L10n.videoPlayer) { router.route(to: .videoPlayerSettings) }
                Button(L10n.playbackQuality) { router.route(to: .playbackQualitySettings) }
                Button(L10n.customProfile) { router.route(to: .customDeviceProfileSettings) }
            }
            Section(L10n.appearance) {
                Picker(L10n.appearance, selection: $appearance)
                ColorPicker(L10n.accentColor, selection: $accent, supportsOpacity: false)
            }
            Section(L10n.customize) {
                Button(L10n.customize) { router.route(to: .customizeViewsSettings) }
                Button(L10n.indicators) { router.route(to: .indicatorSettings) }
            }
            Section {
                Button(L10n.advanced) { router.route(to: .appSettings) }
                Button(L10n.diagnostics) { router.route(to: .diagnostics) }
                Button(L10n.about) { router.route(to: .aboutApp) }
            }
        }
        .navigationTitle(L10n.settings)
        .onChange(of: appearance) { _, value in Defaults[.appearance] = value }
        .onChange(of: accent) { _, value in Defaults[.accentColor] = value }
    }
}

struct AboutAppView: View {
    var body: some View {
        Form {
            Image(.watermelonfinLogo).resizable().scaledToFit().frame(height: 120)
            LabeledContent(L10n.version, value: AppBuildInfo.current.versionDisplay)
            Link("Chen Academy", destination: URL(string: "https://software.chenacademy.org")!)
            Link("GitHub", destination: URL(string: "https://github.com/MrWeiC/WatermelonFin")!)
        }.navigationTitle("WatermelonFin")
    }
}

struct HourMinutePicker: View {
    @Default(.backgroundSignOutInterval)
    private var interval
    var body: some View {
        Form {
            SwiftUI.Slider(value: $interval, in: 0 ... 86400, step: 60) {
                Text(L10n.duration)
            }
            Text(Duration.seconds(interval).formatted(.time(pattern: .hourMinute)))
        }.navigationTitle(L10n.duration)
    }
}
