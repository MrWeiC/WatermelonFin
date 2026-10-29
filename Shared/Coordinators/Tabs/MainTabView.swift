//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import Logging
import SwiftUI

// TODO: move popup to router
//       - or, make tab view environment object

// TODO: fix weird tvOS icon rendering
struct MainTabView: View {

    #if os(iOS)
    @Default(.appearance)
    private var userAppearance
    @Default(.accentColor)
    private var userAccentColor
    @StateObject
    private var tabCoordinator = TabCoordinator {
        TabItem.home
        TabItem.search
        TabItem.media
        TabItem.live
        TabItem.settings
    }
    #else
    @StateObject
    private var tabCoordinator = TabCoordinator {
        TabItem.tvOSTabs
    }
    #endif

    @Environment(\.scenePhase)
    private var scenePhase

    @State
    private var deepLinkTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $tabCoordinator.selectedTabID) {
            ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                NavigationInjectionView(
                    coordinator: tab.coordinator
                ) {
                    tab.item.content
                }
                .environment(\.showsServerConnectionNotice, true)
                .environmentObject(tabCoordinator)
                .environment(\.tabItemSelected, tab.publisher)
                .tabItem {
                    Label(
                        tab.item.title,
                        systemImage: tab.item.systemImage
                    )
                    .labelStyle(tab.item.labelStyle)
                    .symbolRenderingMode(.monochrome)
                    .eraseToAnyView()
                }
                .tag(tab.item.id)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                guard let session = Container.shared.currentUserSession() else { return }
                let service = ServerAddressRecoveryService.shared
                let wasUnavailable = service.unavailableServerIDs.contains(session.server.id)
                let reachable = await service.refreshAddressIfNeeded(
                    serverID: session.server.id, currentURL: session.server.currentURL
                )
                guard !Task.isCancelled else { return }
                if wasUnavailable && reachable { Notifications[.didRequestGlobalRefresh].post() }
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
            }
        }
        #if os(iOS)
        .modifier(MobileTabPresentation())
        .onAppear {
            Defaults[.appearance] = Defaults[.userAppearance]
            Defaults[.accentColor] = Defaults[.userAccentColor]
        }
        .tint(userAccentColor)
        .preferredColorScheme(userAppearance == .system ? nil : (userAppearance == .dark ? .dark : .light))
        #endif
        #if os(tvOS)
        .onAppear {
            if let pendingURL = TopShelfDeepLinkStore.consumePendingURL() {
                handleDeepLink(pendingURL)
            }
        }
        .onReceive(Notifications[.didReceiveDeepLink].publisher) { url in
            TopShelfDeepLinkStore.markHandled(url)
            handleDeepLink(url)
        }
        .onDisappear {
            deepLinkTask?.cancel()
        }
        #endif
    }

    #if os(tvOS)
    private func handleDeepLink(_ url: URL) {
        guard let deepLink = TopShelfDeepLink(url: url) else { return }

        deepLinkTask?.cancel()
        deepLinkTask = Task {
            guard let session = Container.shared.currentUserSession() else { return }

            do {
                let item = try await TopShelfCache.item(id: deepLink.itemID, session: session)

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let homeTab = tabCoordinator.tabs.first(where: { $0.item.id == TabItem.home.id }) else { return }

                    tabCoordinator.selectedTabID = TabItem.home.id
                    homeTab.coordinator.presentedSheet = nil
                    homeTab.coordinator.presentedFullScreen = nil

                    switch deepLink.action {
                    case .item:
                        homeTab.coordinator.push(.item(item: item))
                    case .play:
                        if item.isPlayable {
                            homeTab.coordinator.push(.videoPlayer(item: item))
                        } else {
                            homeTab.coordinator.push(.item(item: item))
                        }
                    }
                }
            } catch {
                Logger.watermelonfin().warning("Failed to open Top Shelf deep link: \(error.localizedDescription)")
            }
        }
    }
    #endif
}

#if os(iOS)
private struct MobileTabPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}
#endif

/// Shared by saved accounts and the active app. This suggests VPN as one possible
/// remedy; public-server reachability cannot identify whether a VPN is enabled.
struct ServerConnectionNotice: View {
    let server: ServerState
    @ObservedObject
    private var recovery = ServerAddressRecoveryService.shared

    var body: some View {
        if recovery.unavailableServerIDs.contains(server.id) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(L10n.serverCannotReach(server.name))
                        .accessibilityIdentifier("server.connection.title")
                } icon: {
                    Image(systemName: "wifi.exclamationmark")
                }
                .font(.headline)
                Text(L10n.serverConnectionHelp)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("server.connection.help")
                Button {
                    Task {
                        let reachable = await recovery.refreshAddressIfNeeded(
                            serverID: server.id, currentURL: server.currentURL
                        )
                        if reachable { Notifications[.didRequestGlobalRefresh].post() }
                    }
                } label: {
                    HStack {
                        if recovery.checkingServerIDs.contains(server.id) { ProgressView() }
                        Text(recovery.checkingServerIDs.contains(server.id) ? L10n.serverConnecting : L10n.retry)
                    }
                    .frame(minHeight: 44)
                }
                .disabled(recovery.checkingServerIDs.contains(server.id))
                .accessibilityIdentifier("server.connection.retry")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("server.connection.notice")
        }
    }
}

struct ServerConnectionNoticeModifier: ViewModifier {
    @Environment(\.showsServerConnectionNotice)
    private var isEnabled

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top) {
            if isEnabled, let server = Container.shared.currentUserSession()?.server {
                ServerConnectionNotice(server: server)
            }
        }
    }
}
