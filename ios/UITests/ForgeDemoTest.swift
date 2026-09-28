import XCTest

/// Drives the real UI end-to-end: type a prompt on the Lovable home screen,
/// send it, watch the agent build, then open the live preview.
final class ForgeDemoTest: XCTestCase {
    func testBuildAppFromPrompt() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            let cancel = springboard.alerts.buttons["Cancel"]
            if cancel.exists { cancel.tap() }
        }

        let app = XCUIApplication()
        app.launchArguments += ["-hasEntered", "YES"]
        app.launch()
        sleep(4)

        let field = app.textFields["promptField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "home composer should exist")
        field.tap()
        sleep(1)
        field.typeText("a beautiful weather dashboard with animated sky gradients, a 5-day forecast, and a temperature chart")
        sleep(2)

        let send = app.buttons["sendButton"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        sleep(8)

        // The build card's Preview button appears when the app goes live.
        let previewButton = app.buttons["previewButton"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 420), "app should go live")
        sleep(3)
        if previewButton.isHittable {
            previewButton.tap()
        } else {
            app.buttons["playButton"].tap()
        }

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 25), "preview should render")
        sleep(12)

        app.buttons["chatBackButton"].tap()
        sleep(4)
    }
}
