import XCTest

/// Opens the newest drawer project: chat with build card, then the preview
/// rendering inside the app.
final class MobileSpotTest: XCTestCase {
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMobileProject() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasEntered", "YES"]
        app.launch()
        sleep(4)

        let menu = app.buttons["menuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        sleep(3)

        var row = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'drawer-'"))
            .firstMatch
        if !row.waitForExistence(timeout: 20) {
            app.swipeDown()
            sleep(2)
            menu.tap()
            sleep(3)
            row = app.buttons
                .matching(NSPredicate(format: "identifier BEGINSWITH 'drawer-'"))
                .firstMatch
        }
        XCTAssertTrue(row.waitForExistence(timeout: 20), "drawer should list at least one project")
        row.tap()
        sleep(4)
        snap(app, "m1-chat")

        let preview = app.buttons["previewButton"].firstMatch
        if preview.waitForExistence(timeout: 8), preview.isHittable {
            preview.tap()
            if app.webViews.firstMatch.waitForExistence(timeout: 25) {
                sleep(14)
                snap(app, "m2-preview")
                if app.buttons["chatBackButton"].waitForExistence(timeout: 5) {
                    app.buttons["chatBackButton"].tap()
                    sleep(2)
                }
            }
        }
    }
}
