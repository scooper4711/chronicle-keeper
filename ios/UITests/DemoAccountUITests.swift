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
        XCTAssertTrue(open.waitForExistence(timeout: 10),
                      "the demo boon PDFs did not download: \(app.debugDescription)")
        app.swipeUp()
        app.swipeUp()
        saveScreenshots("boons")
        open.tap()
        XCTAssertTrue(app.otherElements["QLPreviewControllerView"].waitForExistence(timeout: 5)
                      || app.navigationBars.count > 1, app.debugDescription)
    }

    @MainActor
    func testAnAdventuresChronicleMenuNamesItsActions() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        scrollIntoView(app.buttons["session-details"].firstMatch)
        let chronicle = app.buttons["Attach chronicle sheet"].firstMatch
        XCTAssertTrue(chronicle.waitForExistence(timeout: 5), app.debugDescription)
        scrollIntoView(chronicle)
        chronicle.tap()
        XCTAssertTrue(app.buttons["Attach PDF…"].waitForExistence(timeout: 5), app.debugDescription)
        saveScreenshots("chronicle-menu")
    }

    @MainActor
    func testAnAdventureOpensItsSessionWithTheChronicleSheet() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        let adventure = app.buttons["session-details"].firstMatch
        XCTAssertTrue(adventure.waitForExistence(timeout: 5), app.debugDescription)
        scrollIntoView(adventure)
        adventure.tap()
        XCTAssertTrue(app.staticTexts["Chronicle Sheet"].waitForExistence(timeout: 5), app.debugDescription)
        saveScreenshots("session")
        let sheet = app.buttons["chronicle-sheet-pages"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10),
                      "the demo chronicle sheet did not show: \(app.debugDescription)")
        scrollIntoView(sheet)
        saveScreenshots("session-sheet")
    }

    @MainActor
    func testTheLedgerShowsPurchasesAndTakesANewOne() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        let ledger = app.staticTexts["Gold & Purchases"]
        scrollIntoView(ledger)
        XCTAssertTrue(ledger.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Before the First Adventure"].exists, app.debugDescription)
        saveScreenshots("ledger-start")
        let sale = app.staticTexts["Sold: Leather Armor"]
        scrollIntoView(sale)
        XCTAssertTrue(sale.exists, app.debugDescription)
        saveScreenshots("ledger")
        let add = app.buttons["Add Purchase"].firstMatch
        scrollIntoView(add)
        add.tap()
        let name = app.textFields["purchase-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        name.tap()
        name.typeText("Rope")
        saveScreenshots("purchase-editor")
        let price = app.textFields["Price of one"]
        price.tap()
        price.typeText("5 sp")
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Rope"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testTheAccountMenuOpensAbout() {
        app.buttons["Account"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Leave the Demo"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["About Chronicle Keeper"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), app.debugDescription)
        saveScreenshots("about")
    }

    @MainActor
    func testTheFinderOffersAnAdventureNobodyHasPlayed() {
        app.buttons["Who Can Play…"].firstMatch.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("Clockmaker")
        let adventure = app.staticTexts["#6-14: The Clockmaker's Debt"].firstMatch
        XCTAssertTrue(adventure.waitForExistence(timeout: 5), app.debugDescription)
        saveScreenshots("finder")
        adventure.tap()
        XCTAssertTrue(app.buttons["Other Adventures"].waitForExistence(timeout: 5), app.debugDescription)
        saveScreenshots("finder-candidates")
    }

    /// Scrolls until the element is well clear of the status bar at the foot of the window, which would take a tap
    /// meant for something under it. On the iPhone the adventures start below the fold, and their rows are made
    /// only as they scroll into view.
    @MainActor
    private func scrollIntoView(_ element: XCUIElement) {
        let lowestMiddle = app.windows.firstMatch.frame.maxY * 0.7
        for _ in 0..<6 where !element.exists || element.frame.midY > lowestMiddle {
            app.swipeUp(velocity: .slow)
        }
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
