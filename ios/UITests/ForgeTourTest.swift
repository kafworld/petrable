import XCTest

/// Tours the Petrable UI: home -> left drawer -> newest project chat ->
/// (preview if live) -> home button back. Attaches screenshots throughout.
final class ForgeTourTest: XCTestCase {
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testToolConnectionsSheet() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasEntered", "YES"]
        app.launch()

        let connect = app.buttons["connectToolsButton"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15), "connect tools button should exist")
        connect.tap()

        XCTAssertTrue(
            app.staticTexts["Connected through Convex"].waitForExistence(timeout: 8),
            "tool connections sheet should open"
        )
        XCTAssertTrue(app.staticTexts["Free AI"].exists, "Free AI connection row should be visible")
        XCTAssertTrue(app.staticTexts["Daytona"].exists, "Daytona connection row should be visible")
        snap(app, "tools-connected")

        let startWeb = app.buttons["toolConnections-web"]
        XCTAssertTrue(startWeb.waitForExistence(timeout: 5), "web build shortcut should exist")
        if !startWeb.isHittable {
            app.swipeUp()
            sleep(1)
        }
        startWeb.tap()

        XCTAssertTrue(app.textFields["promptField"].waitForExistence(timeout: 8), "web shortcut should return to composer")
    }

    func testTourLiveProject() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasEntered", "YES"]
        app.launch()
        sleep(4)
        snap(app, "1-home")

        let menu = app.buttons["menuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "home menu button should exist")
        menu.tap()
        sleep(3)
        snap(app, "2-drawer")

        let firstRow = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'drawer-'"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 20), "drawer should list builds")
        firstRow.tap()
        sleep(4)

        XCTAssertTrue(app.buttons["homeButton"].waitForExistence(timeout: 10), "chat should show the home button")
        XCTAssertTrue(app.textFields["chatField"].exists, "chat composer should exist")
        snap(app, "3-chat")

        let preview = app.buttons["previewButton"].firstMatch
        if preview.waitForExistence(timeout: 8) {
            if preview.isHittable {
                preview.tap()
            } else {
                app.buttons["playButton"].tap()
            }
            if app.webViews.firstMatch.waitForExistence(timeout: 25) {
                sleep(8)
                snap(app, "4-preview")
            }
            app.buttons["chatBackButton"].tap()
            sleep(2)
        }

        app.buttons["homeButton"].tap()
        sleep(2)
        XCTAssertTrue(app.textFields["promptField"].waitForExistence(timeout: 10), "home button should return home")
        snap(app, "5-home-again")
    }
}
