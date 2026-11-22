import XCTest

/// The App Store's pictures, from the app's demo content: tabletop-kit's `store-screenshots.sh`.
/// Skipped unless the script names the folder to save into.
final class StoreScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL!

    override func setUpWithError() throws {
        let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? ""
        try XCTSkipIf(path.isEmpty, "Set SCREENSHOT_DIR to make the store screenshots.")
        folder = URL(fileURLWithPath: path)
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testCharacters() throws {
        app.launchArguments = ["-demo"]
        app.launch()
        let character = app.staticTexts["Valeria Stonebrook"].firstMatch
        XCTAssertTrue(character.waitForExistence(timeout: 30), app.debugDescription)
        try save("1-characters")
        character.tap()
        XCTAssertTrue(app.staticTexts["Reputation"].waitForExistence(timeout: 10), app.debugDescription)
        try save("2-character")
        app.swipeUp()
        try save("3-adventures")
    }

    private func save(_ name: String) throws {
        Thread.sleep(forTimeInterval: 1.5)
        let file = folder.appendingPathComponent("\(name).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
    }
}
