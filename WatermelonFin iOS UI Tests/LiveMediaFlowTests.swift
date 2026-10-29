//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import UIKit
import XCTest

/// Requires the loopback live_jellyfin_driver.py with an existing restricted account.
/// Never enters a password into XCTest logs and never performs deletion actions.
final class LiveMediaFlowTests: XCTestCase {
    private var playbackDevice = ""
    private var playbackClient = ""
    @MainActor
    private func selectTab(_ title: String, app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        // iPadOS presents tabs in a top toolbar, not an accessibility TabBar.
        let target = tab.exists ? tab : app.buttons[title].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func signIn(language: String = "en", largeText: Bool = false) async throws -> XCUIApplication {
        continueAfterFailure = false
        playbackClient = UIDevice.current.userInterfaceIdiom == .pad ? "WatermelonFin iPadOS" : "WatermelonFin iOS"
        playbackDevice = UIDevice.current.name.folding(options: .diacriticInsensitive, locale: .current)
            .unicodeScalars.filter { CharacterSet.urlQueryAllowed.contains($0) }.description
        let driver = URL(string: "http://127.0.0.1:18097")!
        var configurationRequest = URLRequest(url: driver.appendingPathComponent("configuration"))
        configurationRequest.timeoutInterval = 3
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: configurationRequest)
        } catch {
            throw XCTSkip("Start Scripts/UITests/live_jellyfin_driver.py to run the opt-in real-server audit")
        }
        let configuration = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(configuration["restricted"] as? Bool, true)
        let serverURL = try XCTUnwrap(configuration["serverURL"] as? String)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingSignedOut", "-uiTestingIsolatedStore", "-AppleLanguages", "(\(language))"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let add = app.buttons["mobile.account.addServer"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        XCTAssertTrue(app.otherElements["mobile.launch.animation"].waitForNonExistence(timeout: 20))
        add.tap()
        let address = app.textFields["mobile.server.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        address.typeText(serverURL)
        app.buttons["mobile.server.connect"].tap()
        let quick = app.buttons["mobile.signIn.quickConnect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 30))
        quick.tap()
        let code = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{6}")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 30))
        var request = URLRequest(url: driver.appendingPathComponent("authorize"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code.label])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (authorization, _) = try await URLSession.shared.data(for: request)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: authorization) as? [String: Bool])
        XCTAssertEqual(result["authorized"], true)
        let home = language == "zh-Hans" ? "首页" : language == "zh-Hant" ? "首頁" : "Home"
        XCTAssertTrue(app.navigationBars[home].waitForExistence(timeout: 40))
        return app
    }

    @MainActor
    func testLiveMediaCardsNavigate() async throws {
        let app = try await signIn()
        selectTab("Media", app: app)
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Home School")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        capture("01-live-media-before-navigation")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "media-accessibility-tree"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(card.isHittable)
        card.tap()
        XCTAssertTrue(app.navigationBars["Home School"].waitForExistence(timeout: 15), "Media card tap must push its library")
        capture("02-live-library-opened")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["All Media"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(
            card.frame.minY,
            app.navigationBars["All Media"].frame.maxY,
            "First card must not overlap navigation title"
        )
        for (label, title) in [
            ("Movies", "Movies"),
            ("Playlists", "Playlists"),
            ("Series", "Shows"),
            ("合集", "合集"),
            ("Favorites", "Favorites"),
        ] {
            let destination = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            if !destination.isHittable { app.swipeUp() }
            XCTAssertTrue(destination.isHittable, "Library card must be tappable: \(label)")
            destination.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15), "Library route must open: \(title)")
            capture("library-\(label)")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["All Media"].waitForExistence(timeout: 10))
        }
    }

    @MainActor
    func testLiveSeriesSeasonsAndEpisodeList() async throws {
        let app = try await signIn()
        selectTab("Media", app: app)
        let shows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Series")).firstMatch
        XCTAssertTrue(shows.waitForExistence(timeout: 20))
        shows.tap()
        let series = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Line Rider")).firstMatch
        XCTAssertTrue(series.waitForExistence(timeout: 20))
        series.tap()
        let season = app.staticTexts["第 1 季"].firstMatch
        for _ in 0 ..< 5 where !season.isHittable { app.swipeUp() }
        capture("series-seasons")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "series-details-tree"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertTrue(season.waitForExistence(timeout: 15), "Line Rider must show its seasons and episode list")
        app.buttons["第 1 季"].tap()
        XCTAssertTrue(app.navigationBars["第 1 季"].waitForExistence(timeout: 15))
        for episode in ["S01E01", "S01E02", "S01E03"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", episode)).firstMatch.waitForExistence(timeout: 20))
        }
        capture("series-season-one-episodes")
        app.navigationBars.buttons.firstMatch.tap()
        let secondSeason = app.buttons["第 2 季"]
        for _ in 0 ..< 3 where !secondSeason.isHittable { app.swipeUp() }
        XCTAssertTrue(secondSeason.isHittable)
        secondSeason.tap()
        XCTAssertTrue(app.navigationBars["第 2 季"].waitForExistence(timeout: 15))
        let secondEpisode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "S02E02")).firstMatch
        XCTAssertTrue(secondEpisode.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "S02E01")).firstMatch.exists)
        capture("series-season-two-episodes")
        secondEpisode.tap()
        let play = app.buttons["mobile.item.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        capture("series-selected-episode")
        play.tap()
        _ = try await waitForPlayback(paused: false, minimumSeconds: 2, itemID: "7e56e268d68f80e2a80e64edd06810a3")
        showControls(app)
        capture("series-selected-episode-playing")
        app.buttons["Close"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["第 2 季"].waitForExistence(timeout: 15))
        XCTAssertTrue(secondEpisode.waitForExistence(timeout: 10))
        capture("series-returned-to-episode-list")
    }

    @discardableResult
    private func waitForPlayback(
        paused: Bool,
        minimumSeconds: Double = 0,
        itemID: String = "d80bf8d9f1067484d153e52a81a87d21",
        audioIndex: Int? = nil,
        subtitleIndex: Int? = nil,
        targetSeconds: Double? = nil
    ) async throws -> Double {
        for _ in 0 ..< 30 {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18097/sessions")!)
            let sessions = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            if let session = sessions.first(where: {
                ($0["client"] as? String) == playbackClient &&
                    ($0["device"] as? String) == playbackDevice &&
                    ($0["itemId"] as? String) == itemID &&
                    (audioIndex == nil || ($0["audioIndex"] as? Int) == audioIndex) &&
                    (subtitleIndex == nil || ($0["subtitleIndex"] as? Int) == subtitleIndex) &&
                    ($0["paused"] as? Bool) == paused &&
                    ($0["positionTicks"] as? Double ?? 0) >= minimumSeconds * 10_000_000 &&
                    (targetSeconds == nil || abs(($0["positionTicks"] as? Double ?? 0) / 10_000_000 - targetSeconds!) < 60)
            }) {
                let evidence = try XCTAttachment(
                    data: JSONSerialization.data(withJSONObject: session, options: [.prettyPrinted]),
                    uniformTypeIdentifier: "public.json"
                )
                evidence.name = "server-playback-paused-\(paused)-minimum-\(Int(minimumSeconds))s"
                evidence.lifetime = .keepAlways
                add(evidence)
                return (session["positionTicks"] as? Double ?? 0) / 10_000_000
            }
            try await Task.sleep(for: .seconds(1))
        }
        XCTFail("Server did not confirm playback state paused=\(paused), position>=\(minimumSeconds)s")
        return -1
    }

    @MainActor
    func testLiveMoviePlaybackControls() async throws {
        let app = try await signIn()
        selectTab("Search", app: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("101忠狗")
        let movie = app.buttons["101忠狗"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 30))
        capture("03-live-search-result")
        movie.tap()
        let play = app.buttons["mobile.item.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        capture("04-live-movie-detail")
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 60), "A real movie must start playing")
        let initialPosition = try await waitForPlayback(paused: false, minimumSeconds: 1)
        try await waitForPlayback(paused: false, minimumSeconds: initialPosition + 2)
        if !app.buttons["Pause"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        capture("05-live-movie-playing")
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        let pausedPosition = try await waitForPlayback(paused: true)
        capture("06-live-movie-paused")
        openTrackMenu("Info", app: app)
        try await Task.sleep(for: .seconds(6))
        XCTAssertTrue(app.navigationBars["Info"].exists, "Playback options must survive auto-hide")
        capture("playback-options")
        app.navigationBars["Info"].buttons["Close"].tap()
        let slider = app.sliders["Playback"]
        XCTAssertTrue(slider.exists)
        let startX = 16 + (slider.frame.width - 32) * pausedPosition / 4756
        let start = slider.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: startX, dy: slider.frame.height / 2))
        let seekFraction = pausedPosition < 2378 ? 0.6 : 0.25
        let target = slider.coordinate(withNormalizedOffset: CGVector(dx: seekFraction, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: target)
        let sliderValue = try XCTUnwrap(slider.value as? String)
        let numericValue = sliderValue.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: "")
        let selectedValue = try XCTUnwrap(
            Double(numericValue.trimmingCharacters(in: .whitespaces)),
            "Unexpected slider value: \(sliderValue)"
        )
        // SwiftUI exposes raw seconds on newer systems and a percentage on older ones.
        let selectedSeconds = sliderValue.contains("%") ? 4756 * selectedValue / 100 : selectedValue
        let soughtPosition = try await waitForPlayback(paused: true, targetSeconds: selectedSeconds)
        XCTAssertGreaterThan(abs(soughtPosition - pausedPosition), 120, "Drag must change actual playback position")
        showControls(app)
        capture("07-live-movie-seek")
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        capture("08-live-movie-landscape")
        if !app.buttons["Close"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        }
        app.buttons["Close"].tap()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars.buttons["Search"].waitForExistence(timeout: 15), "Closing playback must return to item details")
        for _ in 0 ..< 3 where !play.exists {
            app.swipeDown()
        }
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        capture("09-live-movie-closed")
    }

    @MainActor
    private func openPlayback(app: XCUIApplication, query: String, title: String) {
        selectTab("Search", app: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText(query)
        let result = app.buttons[title].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        result.tap()
        let play = app.buttons["mobile.item.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 60))
    }

    @MainActor
    private func showControls(_ app: XCUIApplication) {
        if !app.buttons["Pause"].exists && !app.buttons["Close"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        }
    }

    @MainActor
    private func openTrackMenu(_ title: String, app: XCUIApplication) {
        for _ in 0 ..< 3 {
            showControls(app)
            let button = app.buttons[title]
            if button.waitForExistence(timeout: 2) { button.tap() }
            if app.navigationBars[title].waitForExistence(timeout: 2) { return }
        }
        XCTFail("Track selector must open: \(title)")
    }

    @MainActor
    func testLiveEpisodeAudioSwitch() async throws {
        let app = try await signIn()
        openPlayback(app: app, query: "史派克去受訓", title: "史派克去受訓")
        try await waitForPlayback(paused: false, minimumSeconds: 1, itemID: "12b196fbf9d98b0f76ca5fed61bffc60")
        showControls(app)
        openTrackMenu("Audio", app: app)
        capture("10-live-episode-audio-menu")
        try await Task.sleep(for: .seconds(6))
        XCTAssertTrue(app.buttons["English - AAC - Stereo"].exists, "Track picker must survive overlay timeout")
        app.buttons["English - AAC - Stereo"].tap()
        try await waitForPlayback(paused: false, itemID: "12b196fbf9d98b0f76ca5fed61bffc60", audioIndex: 2)
        capture("11-live-episode-english-audio")
        showControls(app)
        app.buttons["Close"].tap()
    }

    @MainActor
    func testLiveSubtitleSelection() async throws {
        let app = try await signIn()
        openPlayback(app: app, query: "Birth of Japan", title: "Doraemon: Nobita and the Birth of Japan 2016 (2016)")
        try await waitForPlayback(paused: false, minimumSeconds: 1, itemID: "4a1ee8abd880c6472e29d2e76142617a")
        showControls(app)
        openTrackMenu("Subtitles", app: app)
        capture("12-live-subtitle-menu")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'SUBRIP'")).firstMatch.tap()
        try await waitForPlayback(paused: false, itemID: "4a1ee8abd880c6472e29d2e76142617a", subtitleIndex: 2)
        capture("13-live-subtitles-enabled")
        showControls(app)
        openTrackMenu("Subtitles", app: app)
        app.buttons["None"].tap()
        try await waitForPlayback(paused: false, itemID: "4a1ee8abd880c6472e29d2e76142617a", subtitleIndex: -1)
        showControls(app)
        app.buttons["Close"].tap()
    }

    @MainActor
    func testLiveTabsSettingsAndDiagnostics() async throws {
        let app = try await signIn()
        capture("14-live-home")
        XCTAssertFalse(app.buttons["Live TV"].exists)
        for title in ["Search", "Settings"] {
            selectTab(title, app: app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15))
            capture("tab-\(title)")
        }
        let diagnostics = app.buttons["Diagnostics"]
        for _ in 0 ..< 3 where !diagnostics.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(diagnostics.isHittable)
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 10))
        capture("15-live-diagnostics")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        selectTab("Home", app: app)
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLiveChineseMediaLayouts() async throws {
        for language in ["zh-Hans", "zh-Hant"] {
            let app = try await signIn(language: language, largeText: language == "zh-Hans")
            selectTab(language == "zh-Hans" ? "媒体" : "媒體", app: app)
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home School'")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 20))
            XCTAssertTrue(card.isHittable)
            capture("media-\(language)-\(language == "zh-Hans" ? "large-text" : "standard")")
            card.tap()
            XCTAssertTrue(app.navigationBars["Home School"].waitForExistence(timeout: 15))
        }
    }
}
