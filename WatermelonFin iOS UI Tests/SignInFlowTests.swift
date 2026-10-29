//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import XCTest

/// Run with Scripts/UITests/jellyfin_fixture.py listening on loopback port 18096.
final class SignInFlowTests: XCTestCase {
    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAccountFlowScreenshots() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingSignedOut", "-uiTestingIsolatedStore", "-AppleLanguages", "(en)"]
        app.launch()
        let addServer = app.buttons["mobile.account.addServer"]
        XCTAssertTrue(addServer.waitForExistence(timeout: 20))
        XCTAssertTrue(app.otherElements["mobile.launch.animation"].waitForNonExistence(timeout: 20))
        capture("01-account-selection", app: app)
        addServer.tap()
        let address = app.textFields["mobile.server.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        capture("02-server-entry", app: app)
        address.tap()
        address.typeText("http://127.0.0.1:18096/users/\(UUID().uuidString)")
        app.buttons["mobile.server.connect"].tap()
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Preview User"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("03-sign-in-initial", app: app)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Initial sign-in must show all methods before choosing a field")
        username.tap()
        username.typeText("preview")
        capture("04-sign-in-keyboard", app: app)
        XCTAssertTrue(app.staticTexts["Username"].exists, "A filled field must retain a visible label")
        app.swipeUp()
        let quickConnect = app.buttons["Quick Connect"]
        XCTAssertTrue(quickConnect.waitForExistence(timeout: 10))
        if !quickConnect.isHittable { app.swipeUp() }
        quickConnect.tap()
        XCTAssertTrue(app.staticTexts["123456"].waitForExistence(timeout: 15))
        capture("05-quick-connect-code", app: app)
        app.navigationBars["Quick Connect"].buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["123456"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        if !app.buttons["Security"].isHittable { app.swipeDown() }
        app.buttons["Security"].tap()
        XCTAssertTrue(app.navigationBars["Security"].waitForExistence(timeout: 10))
        capture("06-security", app: app)
        XCTAssertTrue(app.navigationBars["Security"].buttons["Close"].exists, "Security must have an explicit dismissal control")
    }

    @MainActor
    private func openFixture(_ scenario: String, language: String = "en", largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingSignedOut", "-uiTestingIsolatedStore", "-AppleLanguages", "(\(language))"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["mobile.account.addServer"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.otherElements["mobile.launch.animation"].waitForNonExistence(timeout: 20))
        app.buttons["mobile.account.addServer"].tap()
        let address = app.textFields["mobile.server.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        address.typeText("http://127.0.0.1:18096/\(scenario)/\(UUID().uuidString)")
        app.buttons["mobile.server.connect"].tap()
        return app
    }

    @MainActor
    func testServerErrorRecovery() {
        let app = openFixture("unavailable")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 15))
        capture("07-server-error", app: app)
        app.alerts.buttons["Dismiss"].tap()
        XCTAssertTrue(app.textFields["mobile.server.address"].isHittable)
        XCTAssertTrue(app.buttons["Connect"].isEnabled)
    }

    @MainActor
    func testLoginFailureThenSuccess() {
        let app = openFixture("users")
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        username.tap()
        username.typeText("Preview User")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("incorrect")
        app.buttons["mobile.signIn.submit"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 15))
        capture("08-login-error", app: app)
        app.alerts.buttons["Dismiss"].tap()
        XCTAssertEqual(username.value as? String, "Preview User")
        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + "fixture-password")
        app.buttons["mobile.signIn.submit"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 20))
        capture("09-signed-in-home", app: app)
        XCTAssertFalse(app.buttons["mobile.signIn.submit"].exists)
    }

    @MainActor
    func testServerLoadingCanCancel() {
        let app = openFixture("slow")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        capture("10-server-loading", app: app)
        cancel.tap()
        XCTAssertTrue(app.buttons["Connect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["mobile.server.address"].exists)
    }

    @MainActor
    func testEmptyUsersAndQuickConnectUnavailable() {
        let app = openFixture("disabled")
        XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Preview User"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mobile.signIn.quickConnect"].exists)
        capture("11-quick-connect-disabled", app: app)
        app.terminate()
        let empty = openFixture("empty")
        XCTAssertTrue(empty.textFields["Username"].waitForExistence(timeout: 20))
        XCTAssertTrue(empty.buttons["mobile.signIn.quickConnect"].waitForExistence(timeout: 10))
        XCTAssertFalse(empty.buttons["Preview User"].exists)
        capture("12-no-public-users", app: empty)
    }

    @MainActor
    func testQuickConnectRecoversAfterRetry() {
        let app = openFixture("quick-retry")
        let quick = app.buttons["mobile.signIn.quickConnect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 20))
        quick.tap()
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertLessThanOrEqual(retry.frame.height, 80, "Retry must stay a compact action, not stretch into a panel")
        XCTAssertTrue(app
            .staticTexts[
                "Quick Connect could not connect to this server. Try again, or close this screen to sign in with your username and password."
            ]
            .exists)
        capture("13-quick-connect-error", app: app)
        retry.tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 25), "Retry must restart polling and finish authentication")
        capture("14-quick-connect-recovered", app: app)
    }

    @MainActor
    func testLanguageAndLargeTextLayouts() {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let app = openFixture("users", language: language)
            XCTAssertTrue(app.textFields["mobile.signIn.username"].waitForExistence(timeout: 20))
            let quick = app.buttons["mobile.signIn.quickConnect"]
            XCTAssertTrue(quick.waitForExistence(timeout: 10))
            XCTAssertTrue(quick.isHittable)
            capture("15-sign-in-\(language)", app: app)
            app.terminate()
        }
        let app = openFixture("users", largeText: true)
        XCTAssertTrue(app.textFields["mobile.signIn.username"].waitForExistence(timeout: 20))
        capture("16-accessibility-text", app: app)
        let quick = app.buttons["mobile.signIn.quickConnect"]
        for _ in 0 ..< 4 where !quick.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(quick.isHittable)
        quick.tap()
        let code = app.staticTexts["123456"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        for _ in 0 ..< 4 where !code.isHittable {
            app.scrollViews["signIn.quickConnect.instructions"].swipeUp()
        }
        XCTAssertTrue(code.isHittable, "Quick Connect code must remain reachable at accessibility text sizes")
        capture("17-quick-connect-large-text", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        for _ in 0 ..< 4 where !code.isHittable {
            app.scrollViews["signIn.quickConnect.instructions"].swipeUp()
        }
        XCTAssertTrue(code.isHittable, "Quick Connect must scroll in landscape")
        XCTAssertTrue(app.frame.contains(code.frame), "All six digits must fit in the screen")
        capture("18-quick-connect-landscape", app: app)
    }

    @MainActor
    func testPasswordWhitespaceIsPreserved() {
        let app = openFixture("spaced-password")
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        username.tap()
        username.typeText("Preview User")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText(" fixture-password ")
        app.buttons["mobile.signIn.submit"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 20), "Passwords must reach the server verbatim")
    }

    @MainActor
    func testLoginLoadingCanCancelAndPasswordVisibility() {
        let app = openFixture("slow-login")
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        let submit = app.buttons["mobile.signIn.submit"]
        XCTAssertFalse(submit.isEnabled)
        username.tap()
        username.typeText("   ")
        XCTAssertFalse(submit.isEnabled, "Whitespace alone is not a username")
        username.typeText("Preview User\n")
        app.secureTextFields["Password"].typeText("fixture-password")
        app.buttons["mobile.password.visibility"].tap()
        XCTAssertEqual(app.textFields["Password"].value as? String, "fixture-password")
        XCTAssertEqual(app.buttons["mobile.password.visibility"].label, "Hide password")
        app.buttons["mobile.password.visibility"].tap()
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        app.secureTextFields["Password"].typeText("x")
        app.buttons["mobile.password.visibility"].tap()
        XCTAssertEqual(
            app.textFields["Password"].value as? String,
            "fixture-passwordx",
            "Editing after re-masking must preserve the full password"
        )
        app.buttons["mobile.password.visibility"].tap()
        app.secureTextFields["Password"].typeText(XCUIKeyboardKey.delete.rawValue + "\n")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        capture("19-login-loading", app: app)
        cancel.tap()
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        XCTAssertTrue(username.isEnabled)
        let unexpectedHome = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.navigationBars["Home"])
        unexpectedHome.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedHome], timeout: 7), .completed, "Cancelled authentication must not sign in later")
        capture("20-login-cancelled", app: app)
    }
}
