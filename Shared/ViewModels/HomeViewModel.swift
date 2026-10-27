//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import CoreStore
import Defaults
import Factory
import Foundation
import Get
import JellyfinAPI
import OrderedCollections

final class HomeViewModel: ViewModel, Stateful {

    // MARK: Action

    enum Action: Equatable {
        case backgroundRefresh
        case error(ErrorMessage)
        case setIsPlayed(Bool, BaseItemDto)
        case refresh
    }

    // MARK: BackgroundState

    enum BackgroundState: Hashable {
        case refresh
    }

    // MARK: State

    enum State: Hashable {
        case content
        case error(ErrorMessage)
        case initial
        case refreshing
    }

    @Published
    private(set) var libraries: [LatestInLibraryViewModel] = []
    @Published
    var resumeItems: OrderedSet<BaseItemDto> = []

    @Published
    var backgroundStates: Set<BackgroundState> = []
    @Published
    var state: State = .initial

    // TODO: replace with views checking what notifications were
    //       posted since last disappear
    @Published
    var notificationsReceived: NotificationSet = .init()

    private var backgroundRefreshTask: AnyCancellable?
    private var refreshTask: AnyCancellable?

    var nextUpViewModel: NextUpLibraryViewModel
    var recentlyAddedViewModel: RecentlyAddedLibraryViewModel

    #if os(tvOS)
    private struct TopShelfNextUpOptions {
        let maxNextUp: TimeInterval
        let resumeNextUp: Bool
    }
    #endif

    /// Initialize HomeViewModel with optional child ViewModels for testing
    /// - Parameters:
    ///   - nextUpViewModel: ViewModel for "Next Up" section (defaults to new instance)
    ///   - recentlyAddedViewModel: ViewModel for "Recently Added" section (defaults to new instance)
    init(
        nextUpViewModel: NextUpLibraryViewModel = .init(),
        recentlyAddedViewModel: RecentlyAddedLibraryViewModel = .init()
    ) {
        self.nextUpViewModel = nextUpViewModel
        self.recentlyAddedViewModel = recentlyAddedViewModel
        super.init()

        Notifications[.itemMetadataDidChange]
            .publisher
            .sink { [weak self] _ in
                // Necessary because when this notification is posted, even with asyncAfter,
                // the view will cause layout issues since it will redraw while in landscape.
                // TODO: look for better solution
                DispatchQueue.main.async {
                    self?.notificationsReceived.insert(.itemMetadataDidChange)
                }
            }
            .store(in: &cancellables)
    }

    func respond(to action: Action) -> State {
        switch action {
        case .backgroundRefresh:

            backgroundRefreshTask?.cancel()
            backgroundStates.insert(.refresh)

            backgroundRefreshTask = Task { [weak self] in
                do {
                    guard let self else { return }

                    nextUpViewModel.send(.refresh)
                    recentlyAddedViewModel.send(.refresh)

                    #if os(tvOS)
                    let topShelfSession = currentSession
                    let topShelfOptions = topShelfNextUpOptions()
                    #endif

                    async let resumeItems = getResumeItems()
                    #if os(tvOS)
                    async let topShelfNextUpItems = getOptionalTopShelfNextUpItems(options: topShelfOptions)
                    #endif

                    let refreshedResumeItems = try await resumeItems
                    #if os(tvOS)
                    let refreshedTopShelfNextUpItems = await topShelfNextUpItems
                    #endif

                    guard !Task.isCancelled else { return }

                    #if os(tvOS)
                    if let session = topShelfSession {
                        await TopShelfCache.update(
                            resumeItems: refreshedResumeItems,
                            nextUpItems: refreshedTopShelfNextUpItems,
                            session: session
                        )
                    }
                    #endif

                    await MainActor.run {
                        self.resumeItems.elements = refreshedResumeItems
                        self.backgroundStates.remove(.refresh)
                    }
                } catch is CancellationError {
                    // cancelled
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.backgroundStates.remove(.refresh)
                        self.send(.error(.init(error.localizedDescription)))
                    }
                }
            }
            .asAnyCancellable()

            return state
        case let .error(error):
            return .error(error)
        case let .setIsPlayed(isPlayed, item): ()
            Task {
                try await setIsPlayed(isPlayed, for: item)

                self.send(.backgroundRefresh)
            }
            .store(in: &cancellables)

            return state
        case .refresh:
            backgroundRefreshTask?.cancel()
            refreshTask?.cancel()

            refreshTask = Task { [weak self] in
                do {
                    try await self?.refresh()

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.state = .content
                    }
                } catch is CancellationError {
                    // cancelled
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let self else { return }
                        self.send(.error(.init(error.localizedDescription)))
                    }
                }
            }
            .asAnyCancellable()

            return .refreshing
        }
    }

    private func refresh() async throws {
        #if os(tvOS)
        let topShelfSession = currentSession
        #endif

        await nextUpViewModel.send(.refresh)
        await recentlyAddedViewModel.send(.refresh)

        #if os(tvOS)
        let topShelfOptions = await topShelfNextUpOptions()
        #endif

        async let resumeItemsTask = getResumeItems()
        async let librariesTask = getLibraries()
        #if os(tvOS)
        async let topShelfNextUpItemsTask = getOptionalTopShelfNextUpItems(options: topShelfOptions)
        #endif

        let resumeItems = try await resumeItemsTask
        let libraries = try await librariesTask
        #if os(tvOS)
        let topShelfNextUpItems = await topShelfNextUpItemsTask
        #endif

        for library in libraries {
            await library.send(.refresh)
        }

        #if os(tvOS)
        if let session = topShelfSession {
            await TopShelfCache.update(
                resumeItems: resumeItems,
                nextUpItems: topShelfNextUpItems,
                session: session
            )
        }
        #endif

        await MainActor.run {
            self.resumeItems.elements = resumeItems
            self.libraries = libraries
        }
    }

    private func getResumeItems() async throws -> [BaseItemDto] {
        let session = try requireSession()

        var parameters = Paths.GetResumeItemsParameters()
        parameters.userID = session.user.id
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.mediaTypes = [.video]
        parameters.limit = 20

        let request = Paths.getResumeItems(parameters: parameters)
        let response = try await session.client.send(request)

        return response.value.items ?? []
    }

    #if os(tvOS)
    @MainActor
    private func topShelfNextUpOptions() -> TopShelfNextUpOptions {
        TopShelfNextUpOptions(
            maxNextUp: Defaults[.Customization.Home.maxNextUp],
            resumeNextUp: Defaults[.Customization.Home.resumeNextUp]
        )
    }

    private func getTopShelfNextUpItems(options: TopShelfNextUpOptions) async throws -> [BaseItemDto] {
        let session = try requireSession()

        var parameters = Paths.GetNextUpParameters()
        parameters.enableUserData = true
        parameters.fields = .MinimumFields
        parameters.limit = TopShelfCache.maxItemsPerSection
        if options.maxNextUp > 0 {
            parameters.nextUpDateCutoff = Date.now.addingTimeInterval(-options.maxNextUp)
        }
        parameters.enableRewatching = options.resumeNextUp
        parameters.userID = session.user.id

        let request = Paths.getNextUp(parameters: parameters)
        let response = try await session.client.send(request)

        return response.value.items ?? []
    }

    private func getOptionalTopShelfNextUpItems(options: TopShelfNextUpOptions) async -> [BaseItemDto] {
        do {
            return try await getTopShelfNextUpItems(options: options)
        } catch is CancellationError {
            return []
        } catch {
            logger.warning("Unable to refresh Top Shelf Next Up items: \(error.localizedDescription)")
            return []
        }
    }
    #endif

    private func getLibraries() async throws -> [LatestInLibraryViewModel] {
        let session = try requireSession()

        let parameters = Paths.GetUserViewsParameters(userID: session.user.id)
        let userViewsPath = Paths.getUserViews(parameters: parameters)
        async let userViews = session.client.send(userViewsPath)

        async let excludedLibraryIDs = getExcludedLibraries()

        return try await (userViews.value.items ?? [])
            .intersecting(
                [
                    .homevideos,
                    .movies,
                    .musicvideos,
                    .tvshows,
                ],
                using: \.collectionType
            )
            .subtracting(excludedLibraryIDs, using: \.id)
            .map { LatestInLibraryViewModel(parent: $0) }
    }

    // TODO: use the more updated server/user data when implemented
    private func getExcludedLibraries() async throws -> [String] {
        let currentUserPath = Paths.getCurrentUser
        guard let userSession = currentSession else { return [] }

        let response = try await userSession.client.send(currentUserPath)

        return response.value.configuration?.latestItemsExcludes ?? []
    }

    private func setIsPlayed(_ isPlayed: Bool, for item: BaseItemDto) async throws {
        guard let itemID = item.id else { return }

        let session = try requireSession()
        let request: Request<UserItemDataDto>

        if isPlayed {
            request = Paths.markPlayedItem(
                itemID: itemID,
                userID: session.user.id
            )
        } else {
            request = Paths.markUnplayedItem(
                itemID: itemID,
                userID: session.user.id
            )
        }

        _ = try await session.client.send(request)
    }
}
