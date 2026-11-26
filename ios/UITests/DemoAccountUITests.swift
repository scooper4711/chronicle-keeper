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
        let adventures = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Adventures ('")).firstMatch
        XCTAssertTrue(adventures.exists, app.debugDescription)
        saveScreenshots("character")
    }

    @MainActor
    func testASectionFoldsAwayAndBack() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        let boons = app.buttons["Boons (2)"]
        scrollIntoView(boons)
        XCTAssertTrue(boons.waitForExistence(timeout: 5), app.debugDescription)
        let open = app.buttons["Open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        boons.tap()
        XCTAssertEqual(boons.value as? String, "Collapsed")
        XCTAssertTrue(open.waitForNonExistence(timeout: 5), app.debugDescription)
        saveScreenshots("boons-collapsed")
        boons.tap()
        XCTAssertEqual(boons.value as? String, "Expanded")
        XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testACharactersBoonsCanBeOpened() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        let boons = app.buttons["Boons (2)"]
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
    func testRewardsWaitingToBeClaimedAreSignaled() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        let sparkle = app.buttons["claim-sparkle"].firstMatch
        XCTAssertTrue(sparkle.waitForExistence(timeout: 10),
                      "the demo's free rewards were not found: \(app.debugDescription)")
        saveScreenshots("claim-sparkles")
        let ready = app.staticTexts["Ready to Claim (3)"]
        scrollIntoView(ready)
        XCTAssertTrue(ready.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["claim-on-paizo"].firstMatch.exists, app.debugDescription)
        saveScreenshots("ready-to-claim")
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

    /// The demo's sheet names another character: the warning shows, the confirmation has what was read, and the
    /// warning can be cleared.
    @MainActor
    func testAChronicleSheetsWarningIsCheckedAndCleared() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        let adventure = app.buttons["session-details"].firstMatch
        XCTAssertTrue(adventure.waitForExistence(timeout: 5), app.debugDescription)
        scrollIntoView(adventure)
        adventure.tap()
        let clear = app.buttons["Clear Warning"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5),
                      "the demo sheet's warning did not show: \(app.debugDescription)")
        saveScreenshots("sheet-warning")
        app.buttons["sheet-reading-edit"].firstMatch.tap()
        let number = app.textFields["sheet-field-characterNumber"]
        XCTAssertTrue(number.waitForExistence(timeout: 10), app.debugDescription)
        let filled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '123456-2002'"), object: number)
        XCTAssertEqual(XCTWaiter.wait(for: [filled], timeout: 10), .completed, app.debugDescription)
        saveScreenshots("sheet-confirmation")
        app.buttons["sheet-keep"].firstMatch.tap()
        XCTAssertTrue(clear.waitForExistence(timeout: 5), app.debugDescription)
        clear.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    /// Pip has a chronicle sheet for a session paizo.com doesn't list yet: the adventures' title counts it, its row
    /// says so in words and with a badge, the level says it is counted, and its details say where its numbers
    /// come from.
    @MainActor
    func testAnUnreportedChronicleIsMarkedAsNotReported() {
        app.staticTexts["Pip Underbough"].firstMatch.tap()
        XCTAssertTrue(element("unreported-totals").waitForExistence(timeout: 5), app.debugDescription)
        let adventures = app.buttons["Adventures (3 · 1 not reported)"]
        scrollIntoView(adventures)
        XCTAssertTrue(adventures.waitForExistence(timeout: 5), app.debugDescription)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Not reported yet'")).firstMatch
        scrollIntoView(row)
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("unreported-badge").exists, app.debugDescription)
        saveScreenshots("unreported")
        row.tap()
        XCTAssertTrue(element("unreported-banner").waitForExistence(timeout: 5), app.debugDescription)
        saveScreenshots("unreported-session")
    }

    /// An element by its identifier, whatever kind the system makes of it.
    @MainActor
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func testTheLedgerShowsPurchasesAndTakesANewOne() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        let ledger = app.buttons["Gold & Purchases"]
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
        app.steppers.firstMatch.buttons.element(boundBy: 1).tap()
        saveScreenshots("purchase-editor-filled")
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Rope, 2 of them"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testAMarkedPurchaseIsLinkedToAnotherCharactersBoonAndUnlinked() {
        app.staticTexts["Valeria Stonebrook"].firstMatch.tap()
        let warning = app.buttons["May not be Society legal"].firstMatch
        scrollIntoView(warning)
        XCTAssertTrue(warning.waitForExistence(timeout: 5), app.debugDescription)
        warning.tap()
        let link = app.buttons["Link a Boon or Chronicle Sheet…"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
        saveScreenshots("legality-warning")
        // Turning the device can close the popover.
        if !link.exists { warning.tap() }
        link.tap()
        let boon = app.buttons["Lantern Fair Keepsake"].firstMatch
        XCTAssertTrue(boon.waitForExistence(timeout: 5), "Pip's boon was not offered: \(app.debugDescription)")
        saveScreenshots("link-picker")
        boon.tap()
        let check = app.buttons["Linked to a boon"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(warning.exists, app.debugDescription)
        saveScreenshots("ledger-linked")
        check.tap()
        let unlink = app.buttons["Unlink"].firstMatch
        XCTAssertTrue(unlink.waitForExistence(timeout: 5), app.debugDescription)
        saveScreenshots("legality-check")
        if !unlink.exists { check.tap() }
        unlink.tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 5), app.debugDescription)
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
