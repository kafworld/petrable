import XCTest

/// Exercises the model selector menu and the voice record/transcribe cycle.
final class VoiceModelSpotTest: XCTestCase {
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testModelMenuAndMic() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasEntered", "YES"]
        app.launch()
        sleep(4)

        let menu = app.buttons["modelMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "model menu should exist")
        menu.tap()

        let smart = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Gemini Pro'")).firstMatch
        XCTAssertTrue(smart.waitForExistence(timeout: 5), "Gemini Pro option should be in the menu")
        smart.tap()
        // The chip's own label becomes the selection (menu items are buttons,
        // the composer chip is the static text underneath).
        XCTAssertTrue(
            waitForLabel(app.buttons["modelMenu"], contains: "Gemini Pro"),
            "model chip should switch to Gemini Pro"
        )
        sleep(1)
        snap(app, "v1-model-menu")
        let smartLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Gemini Pro'")).firstMatch
        XCTAssertTrue(smartLabel.waitForExistence(timeout: 5), "composer should show Gemini Pro")
        snap(app, "v2-smart-selected")

        // Voice: start recording (red stop state), then stop and transcribe.
        let mic = app.buttons["voiceButton"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        mic.tap()
        sleep(3)
        snap(app, "v3-recording")
        mic.tap()
        sleep(7) // transcribe round trip (silence -> empty text is fine)
        snap(app, "v4-after-transcribe")

        // Leave the model back on the default (Gemini Flash).
        menu.tap()
        let balanced = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Gemini Flash'")).firstMatch
        XCTAssertTrue(balanced.waitForExistence(timeout: 5))
        balanced.tap()
        XCTAssertTrue(
            waitForLabel(app.buttons["modelMenu"], contains: "Gemini Flash"),
            "model chip should switch back to Gemini Flash"
        )
        sleep(1)
    }

    /// Poll an element's accessibility label until it contains the text.
    private func waitForLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label.contains(text) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.label.contains(text)
    }

    func testHomePlusMenuShowsActions() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasEntered", "YES"]
        app.launch()

        let plus = app.buttons["homePlusMenu"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "home plus menu should exist")
        plus.tap()

        let iphoneAction = app.buttons["iPhone App"]
        XCTAssertTrue(iphoneAction.waitForExistence(timeout: 5), "plus menu should show iPhone App action")
        XCTAssertTrue(app.buttons["Web App"].exists, "plus menu should show Web App action")
        XCTAssertTrue(app.buttons["Todo App Example"].exists, "plus menu should show Todo App Example action")

        iphoneAction.tap()
        let prompt = app.textFields["promptField"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "prompt field should remain available after picking an action")
        XCTAssertTrue(prompt.value as? String == "Make a polished iPhone app for ", "iPhone App action should seed the prompt")
    }
}
