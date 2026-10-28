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
    func testFirstRunCanOpenServerSetup() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingSignedOut"]
        app.launch()
        let manual = app.buttons["server.manualAddress"]
        XCTAssertTrue(manual.waitForExistence(timeout: 20), "An unconfigured launch should open discovery automatically")
        manual.tap()
        let address = app.textFields["mobile.server.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["mobile.launch.animation"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertTrue(address.isHittable, "Returning should preserve the server discovery screen")
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
