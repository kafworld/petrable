import XCTest

/// Marketing screenshot walk. This test is intentionally lenient:
/// it taps around the UI and captures whatever state is visible.
/// Screenshots are written to /tmp/petrable-shots on the host (runner-side).
final class ScreenshotTourUITest: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let dir = URL(fileURLWithPath: "/tmp/petrable-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = app.screenshot()
        try? s.image.pngData()?.write(to: dir.appendingPathComponent("\(name).png"))
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testScreenshotTour() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasEntered", "YES"]
        app.launch()
        sleep(3)

        // Welcome only appears when hasEntered is reset outside the test.
        if app.buttons["Enter App"].waitForExistence(timeout: 5) {
            shot(app, "01-welcome")
            app.buttons["Enter App"].tap()
            sleep(2)
        }

        if app.buttons["modelMenu"].waitForExistence(timeout: 15) {
            shot(app, "02-home")
            app.buttons["modelMenu"].tap()
            sleep(2)
            shot(app, "03-models")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.15)).tap()
            sleep(1)
        }

        if app.buttons["connectToolsButton"].waitForExistence(timeout: 6) {
            app.buttons["connectToolsButton"].tap()
            sleep(2)
            shot(app, "04-tools")
            let startWeb = app.buttons["toolConnections-web"]
            if startWeb.waitForExistence(timeout: 5) {
                if !startWeb.isHittable { app.swipeUp(); sleep(1) }
                startWeb.tap()
                sleep(1)
            }
        }

        // The menu (drawer) — opened and shot regardless of how we reach chat.
        if app.buttons["menuButton"].waitForExistence(timeout: 6) {
            app.buttons["menuButton"].tap()
            sleep(2)
            shot(app, "07-drawer")
            // Tap the scrim (right of the drawer) to close it again.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            sleep(1)
        }

        // Prefer the deterministic deep link to the success-story project
        // (drawer taps land on the wrong row on this beta sim). Handles the
        // iOS "Open in …?" confirmation if the system raises one.
        var gotChat = false
        if let url = URL(string: "forge://project/jd78hebhzsv1t63j4rzdt5n7r58f9ccs") {
            app.open(url)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if springboard.buttons["Open"].waitForExistence(timeout: 4) {
                springboard.buttons["Open"].tap()
            }
            if app.textFields["chatField"].waitForExistence(timeout: 15) {
                sleep(2)
                shot(app, "05-chat")
                gotChat = true
            }
        }

        // Fallback: walk the drawer (may land on whatever row the sim hits).
        if !gotChat, app.buttons["menuButton"].waitForExistence(timeout: 6) {
            app.buttons["menuButton"].tap()
            sleep(2)
            let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'drawer-'")).firstMatch
            if firstRow.waitForExistence(timeout: 15) {
                firstRow.tap()
                if app.textFields["chatField"].waitForExistence(timeout: 15) {
                    sleep(2)
                    shot(app, "05-chat")
                }
                if app.buttons["chatBackButton"].exists {
                    app.buttons["chatBackButton"].tap()
                    sleep(2)
                }
                if app.buttons["homeButton"].exists {
                    app.buttons["homeButton"].tap()
                    sleep(1)
                }
            }
        }

        // Return to home for the closing shot (either branch may be in chat).
        if app.buttons["homeButton"].exists {
            app.buttons["homeButton"].tap()
            sleep(1)
        }

        shot(app, "06-home-final")
    }

    /// Self-contained deep-link verification: launches the app warm, opens
    /// forge:// URL via XCUIApplication.open (raises the system confirmation),
    /// accepts it, then captures the chat — no shell/dialog timing games.
    func testAcceptOpenDialog() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasEntered", "YES"]
        app.launch()
        sleep(2)

        if let url = URL(string: "forge://project/jd78hebhzsv1t63j4rzdt5n7r58f9ccs") {
            app.open(url)
        }

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 10) {
            springboard.buttons["Open"].tap()
        }

        if app.textFields["chatField"].waitForExistence(timeout: 15) {
            sleep(2)
            let dir = URL(fileURLWithPath: "/tmp/petrable-shots", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let s = XCUIScreen.main.screenshot()
            try? s.image.pngData()?.write(to: dir.appendingPathComponent("05-chat.png"))
            let a = XCTAttachment(screenshot: s)
            a.name = "deeplink-chat"
            a.lifetime = .keepAlways
            add(a)
        }
    }
}
