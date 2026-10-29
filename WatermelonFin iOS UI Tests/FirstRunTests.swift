//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import XCTest

final class FirstRunTests: XCTestCase {
    @MainActor
    func testDeviceLanguageSelectsEnglishAndChinese() {
        let app = XCUIApplication()
        for (language, expectedTitle) in [
            ("en", "Add server"),
            ("zh-Hans", "添加服务器"),
            ("zh-Hant", "添加伺服器"),
            ("is", "Add server"),
        ] {
            app.launchArguments = ["-uiTestingSignedOut", "-uiTestingIsolatedStore", "-AppleLanguages", "(\(language))"]
            app.launch()
            let addServer = app.buttons["mobile.account.addServer"]
            XCTAssertTrue(addServer.waitForExistence(timeout: 20))
            XCTAssertTrue(app.otherElements["mobile.launch.animation"].waitForNonExistence(timeout: 20))
            XCTAssertEqual(addServer.label, expectedTitle, "Incorrect UI language for \(language)")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "First run — \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    @MainActor
    func testFirstRunCanOpenServerSetup() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingSignedOut", "-uiTestingIsolatedStore"]
        app.launch()
        let addServer = app.buttons["mobile.account.addServer"]
        XCTAssertTrue(addServer.waitForExistence(timeout: 20))
        let animation = app.otherElements["mobile.launch.animation"]
        XCTAssertTrue(animation.waitForNonExistence(timeout: 20))
        XCTAssertFalse(app.textFields["mobile.server.address"].exists, "Launch must not present server setup")
        addServer.tap()
        let address = app.textFields["mobile.server.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["server.searchAgain"].exists, "Discovery is unavailable in this release")
        XCTAssertFalse(app.otherElements["server.searching"].exists)
        XCTAssertFalse(app.otherElements["mobile.launch.animation"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertTrue(address.isHittable, "Returning should preserve the manual server setup screen")
        XCTAssertFalse(app.buttons["server.searchAgain"].exists, "Discovery is unavailable in this release")
        XCTAssertFalse(app.otherElements["server.searching"].exists)
        XCTAssertFalse(app.otherElements["mobile.launch.animation"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPhone server setup"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertTrue(address.isHittable, "Server setup must remain usable after rotation on iPhone and iPad")
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "Server setup landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
    }
}
