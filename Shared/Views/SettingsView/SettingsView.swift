//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import JellyfinAPI
import SwiftUI

struct SettingsView: View {

    @Router
    var router

    #if os(iOS)
    @Default(.userAppearance)
    private var appearance
    #endif

    @Default(.userAccentColor)
    private var accentColor

    @Default(.VideoPlayer.videoPlayerType)
    private var videoPlayerType

    @StateObject
    private var viewModel = SettingsViewModel()

    // MARK: - Body

    var body: some View {
        Form(image: .watermelonfinLogo) {
            accountAndServerSection
            videoPlayerSection
            mediaAndAppearanceSection
            diagnosticsSection
        }
        #if os(iOS)
        .navigationTitle(L10n.settings)
        .navigationBarCloseButton {
            router.dismiss()
        }
        #endif
    }

    // MARK: - Account and Server Section

    private var accountAndServerSection: some View {
        Section(L10n.accountAndServer) {
            if let userSession = viewModel.userSession {
                UserProfileRow(user: userSession.user.data) {
                    router.route(to: .userProfile(viewModel: viewModel))
                }

                ChevronButton(
                    L10n.server,
                    action: {
                        router.route(to: .editServer(server: userSession.server))
                    }
                ) {
                    EmptyView()
                } subtitle: {
                    serverSubtitle(for: userSession.server)
                }

                #if os(iOS)
                if userSession.user.permissions.isAdministrator {
                    ChevronButton(L10n.dashboard) {
                        router.route(to: .adminDashboard)
                    }
                }
                #endif
            } else {
                Text(L10n.unauthorizedUser)
            }

            Button {
                UIDevice.impact(.medium)
                viewModel.signOut()
                router.dismiss()
            } label: {
                Label(L10n.switchUser, systemImage: "person.2")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
        }
    }

    private func serverSubtitle(for server: ServerState) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Label {
                Text(server.name)
            } icon: {
                if !server.isVersionCompatible {
                    Image(systemName: "exclamationmark.circle.fill")
                }
            }
            .labelStyle(.sectionFooterWithImage(imageStyle: .orange))

            Text(server.currentURL.host ?? server.currentURL.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Playback Section

    private var videoPlayerSection: some View {
        #if os(iOS)
        Section(L10n.playback) {
            Picker(L10n.videoPlayerType, selection: $videoPlayerType)

            ChevronButton(L10n.nativePlayer) {
                router.route(to: .nativePlayerSettings)
            }

            ChevronButton(L10n.videoPlayer) {
                router.route(to: .videoPlayerSettings)
            }

            ChevronButton(L10n.playbackQuality) {
                router.route(to: .playbackQualitySettings)
            }
        } learnMore: {
            LabeledContent(
                "WatermelonFin",
                value: L10n.playerWatermelonFinDescription
            )
            LabeledContent(
                L10n.native,
                value: L10n.playerNativeDescription
            )
        }
        #else
        Section(L10n.playback) {
            ListRowMenu(L10n.videoPlayerType, selection: $videoPlayerType)
                .focusedValue(\.formLearnMore, videoPlayerTypeLearnMore)

            ChevronButton(L10n.videoPlayer) {
                router.route(to: .videoPlayerSettings)
            }

            ChevronButton(L10n.playbackQuality) {
                router.route(to: .playbackQualitySettings)
            }
        }
        #endif
    }

    @LabeledContentBuilder
    private var videoPlayerTypeLearnMore: AnyView {
        LabeledContent(
            "WatermelonFin",
            value: L10n.playerWatermelonFinDescription
        )
        LabeledContent(
            L10n.native,
            value: L10n.playerNativeDescription
        )
    }

    // MARK: - Media and Appearance Section

    @ViewBuilder
    private var mediaAndAppearanceSection: some View {
        Section(L10n.mediaAndAppearance) {
            #if os(tvOS)
            ChevronButton(L10n.media) {
                router.route(to: .media)
            }
            #endif

            #if os(iOS)
            Picker(L10n.appearance, selection: $appearance)
            #endif

            ChevronButton(L10n.customize) {
                router.route(to: .customizeViewsSettings)
            }
        }

        #if os(iOS)
        Section {
            ColorPicker(L10n.accentColor, selection: $accentColor, supportsOpacity: false)
        } footer: {
            Text(L10n.viewsMayRequireRestart)
        }
        #endif
    }

    // MARK: - Diagnostics Section

    private var diagnosticsSection: some View {
        Section(L10n.advancedAndDiagnostics) {
            LabeledContent {
                Text(AppBuildInfo.current.commitDisplay)
            } label: {
                Text(verbatim: "Commit")
            }
            .focusable(false)

            ChevronButton(
                L10n.diagnostics,
                subtitle: L10n.diagnosticsDescription
            ) {
                router.route(to: .diagnostics)
            }

            #if DEBUG && os(iOS)
            ChevronButton(L10n.debug) {
                router.route(to: .debugSettings)
            }
            #endif
        }
    }
}
