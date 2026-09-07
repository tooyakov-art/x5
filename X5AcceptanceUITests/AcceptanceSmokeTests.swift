import XCTest

/// Real app and network, not X5_HOME_QA_PREVIEW. No account creation, purchase,
/// generation, publication or message sending. Only the dedicated review login.
final class AcceptanceSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-x5.language", "en"]
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 { capture("failure-last-screen") }
        app.terminate()
    }

    func test01GuestValidationAndBack() throws {
        let emailChoice = app.buttons["Continue with Email"]
        XCTAssertTrue(emailChoice.waitForExistence(timeout: 30))
        capture("A01-login-options")
        emailChoice.tap()
        let email = app.textFields.firstMatch
        let password = app.secureTextFields.firstMatch
        let submit = app.buttons["Sign in to Xfive marketing"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        XCTAssertFalse(submit.isEnabled)
        email.tap()
        email.typeText("invalid-email")
        password.tap()
        password.typeText("not-a-real-password")
        XCTAssertFalse(submit.isEnabled)
        app.buttons["Back"].tap()
        XCTAssertTrue(emailChoice.waitForExistence(timeout: 5))
        emailChoice.tap()
        XCTAssertEqual(email.value as? String, "Email")
        XCTAssertFalse(submit.isEnabled)
        capture("A01-invalid-input-cleared")
        app.buttons["Back"].tap()
    }

    func test02ReviewLoginReadOnlyScreensAndSessionPersistence() throws {
        let emailChoice = app.buttons["Continue with Email"]
        XCTAssertTrue(emailChoice.waitForExistence(timeout: 30))
        emailChoice.tap()
        let bundle = Bundle(for: Self.self)
        func credential(_ name: String) throws -> String {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "txt"))
            return try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText(try credential("demo_user"))
        app.secureTextFields.firstMatch.tap()
        app.secureTextFields.firstMatch.typeText(try credential("demo_password"))
        app.buttons["Sign in to Xfive marketing"].tap()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 60), "Real review login must finish profile routing")
        capture("A02-authenticated-home")

        tabs.buttons["Profile"].tap()
        let store = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Store")).firstMatch
        for _ in 0..<4 where !store.isHittable { app.swipeUp() }
        XCTAssertTrue(store.waitForExistence(timeout: 10))
        store.tap()
        XCTAssertTrue(app.navigationBars["Store"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1000 credits"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2000 credits"].exists)
        capture("P01-store-packs-no-purchase")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["5000 credits"].waitForExistence(timeout: 5))
        capture("P01-store-third-pack-no-purchase")
        app.buttons["Done"].tap()

        tabs.buttons["Hub"].tap()
        XCTAssertTrue(app.staticTexts["Hub"].waitForExistence(timeout: 10))
        capture("H01-hub-read-only")
        tabs.buttons["CourseUP"].tap()
        XCTAssertTrue(app.staticTexts["No published courses yet"].waitForExistence(timeout: 30),
                      "The review account currently has zero published courses; never substitute invented lessons")
        XCTAssertFalse(app.staticTexts["Вайбкодинг для маркетолога"].exists)
        app.buttons["Refresh"].tap()
        XCTAssertTrue(app.staticTexts["No published courses yet"].waitForExistence(timeout: 30))
        capture("C01-course-catalog-read-only")
        app.terminate()
        app.launch()
        let restored = app.tabBars.firstMatch.waitForExistence(timeout: 60)
        capture("A02-cold-restart-result")
        XCTAssertTrue(restored)
        XCTAssertFalse(app.buttons["Continue with Email"].exists)
        capture("A02-session-restored")
    }
}
