import XCTest

/// Drives the app in the demo account on iPhone and iPad: the characters, one character's details, and the account
/// menu. Run with `scripts/run-uitests.sh iPhone|iPad`; with SCREENSHOT_DIR set, each test saves screenshots there in
/// portrait and landscape.
final class DemoAccountUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Valeria Stonebrook"].firstMatch.waitForExistence(timeout: 30),
                      "the demo characters did not load: \(app.debugDescription)")
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    @MainActor
    func testTheSidebarListsTheCharactersByCampaign() {
        XCTAssertTrue(app.staticTexts["Pathfinder Society (2nd Edition)"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Starfinder Society (2nd Edition)"].exists, app.debugDescription)
        saveScreenshots("characters")
    }

    @MainActor
    func testChoosingACharacterShowsTheirReputationAndAdventures() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Reputation"].waitForExistence(timeout: 5), app.debugDescription)
        let adventures = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Adventures ('")).firstMatch
        XCTAssertTrue(adventures.exists, app.debugDescription)
        saveScreenshots("character")
    }

    @MainActor
    func testACharactersBoonsCanBeOpened() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        let boons = app.staticTexts["Boons (2)"]
        XCTAssertTrue(boons.waitForExistence(timeout: 5), app.debugDescription)
        let open = app.buttons["Open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the demo boon PDFs did not download: \(app.debugDescription)")
        app.swipeUp()
        app.swipeUp()
        saveScreenshots("boons")
        open.tap()
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].waitForExistence(timeout: 5)
                      || app.navigationBars.count > 1, app.debugDescription)
    }

    @MainActor
    func testTheAccountMenuOpensAbout() {
        app.buttons["Account"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Leave the Demo"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["About Character Keeper"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), app.debugDescription)
        saveScreenshots("about")
    }

    @MainActor
    func testTheFinderListsTheAdventuresPlayed() {
        app.buttons["Who Can Play…"].firstMatch.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThan(app.cells.count, 0, app.debugDescription)
        saveScreenshots("finder")
    }

    /// Writes the screen in portrait and in landscape to SCREENSHOT_DIR, when it is set.
    @MainActor
    private func saveScreenshots(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !folder.isEmpty else { return }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        for (orientation, label) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orientation
            sleep(1)
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(device)-\(name)-\(label).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
    }
}
