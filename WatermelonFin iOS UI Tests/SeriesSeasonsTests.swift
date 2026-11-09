//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import XCTest

/// Run with `python3 Scripts/UITests/jellyfin_fixture.py --port 18098` listening on loopback.
final class SeriesSeasonsTests: XCTestCase {
    private let fixture = "http://127.0.0.1:18098"

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openSeries(_ scenario: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let probe = URL(string: "\(fixture)/\(scenario)/probe/system/info/public")!
        guard (try? Data(contentsOf: probe)) != nil else {
            throw XCTSkip("Start Scripts/UITests/jellyfin_fixture.py --port 18098 to run the series fixture tests")
        }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingSignedOut", "-uiTestingIsolatedStore", "-AppleLanguages", "(en)"]
        app.launch()
        let add = app.buttons["mobile.account.addServer"]
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        XCTAssertTrue(app.otherElements["mobile.launch.animation"].waitForNonExistence(timeout: 20))
        add.tap()
        let manual = app.buttons["server.manualAddress"].firstMatch
        if manual.waitForExistence(timeout: 5) { manual.tap() }
        let address = app.textFields["mobile.server.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        address.typeText("\(fixture)/\(scenario)/\(UUID().uuidString)")
        app.buttons["mobile.server.connect"].tap()
        let quick = app.buttons["mobile.signIn.quickConnect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 20))
        quick.tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 25))
        let show = app.buttons["Fixture Show"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        show.tap()
        return app
    }

    @MainActor
    func testManySeasonsCanBeBrowsed() throws {
        let app = try openSeries("series")
        let seasons = app.buttons.matching(identifier: "mobile.series.season")
        XCTAssertTrue(seasons.firstMatch.waitForExistence(timeout: 20), "Series page must list its seasons")
        XCTAssertEqual(seasons.count, 12)
        XCTAssertTrue(app.buttons["Season 1"].isSelected, "First season starts selected when nothing is in progress")
        XCTAssertTrue(app.buttons["Episode 1 of season 1"].waitForExistence(timeout: 20), "Selected season must show its episodes")
        capture("series-many-seasons", app: app)

        app.buttons["Season 2"].tap()
        XCTAssertTrue(app.buttons["Episode 1 of season 2"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Season 2"].isSelected)

        // Reach a season that starts off-screen on compact width.
        for _ in 0 ..< 6 where !app.buttons["Season 12"].isHittable {
            app.buttons.matching(identifier: "mobile.series.season").allElementsBoundByIndex
                .last(where: \.isHittable)?.swipeLeft()
        }
        XCTAssertTrue(app.buttons["Season 12"].isHittable)
        app.buttons["Season 12"].tap()
        let episode = app.buttons["Episode 3 of season 12"]
        XCTAssertTrue(episode.waitForExistence(timeout: 20))
        capture("series-last-season", app: app)

        episode.tap()
        XCTAssertTrue(app.buttons["mobile.item.play"].waitForExistence(timeout: 20), "Episode page must offer playback")
        capture("series-episode-detail", app: app)
    }

    @MainActor
    func testSingleSeasonIsListed() throws {
        let app = try openSeries("series-single")
        let seasons = app.buttons.matching(identifier: "mobile.series.season")
        XCTAssertTrue(seasons.firstMatch.waitForExistence(timeout: 20), "A single-season series must still list its season")
        XCTAssertEqual(seasons.count, 1)
        XCTAssertTrue(app.buttons["Episode 2 of season 1"].waitForExistence(timeout: 20))
        capture("series-single-season", app: app)
    }
}
