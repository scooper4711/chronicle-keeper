import Foundation
import Testing
@testable import CharacterKeeperKit

private let base = URL(string: "https://paizo.com")!  // swiftlint:disable:this force_unwrapping
private let pdfBytes = Data("%PDF-1.4 a boon".utf8)

private func fixtureBoons() throws -> [Boon] {
    try BoonsPageParser.boons(in: Fixture.text("boons"), base: base)
}

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("boon-tests-\(UUID().uuidString)")
}

struct BoonsPageParserTests {
    @Test func readsEveryPurchasedBoonAndSkipsThePurchaseForms() throws {
        let boons = try fixtureBoons()
        #expect(boons.map(\.characterName) ==
                ["Valeria Stonebrook", "Valeria Stonebrook", "Pip Underbough", "Pip Underbough", "Someone Else"])
        #expect(boons[1].name == "Envoy's Alliance Gear")
        #expect(boons[1].summary.hasPrefix("Gain access to Envoy's Alliance gear"))
    }

    @Test func readsQuantityAndUses() throws {
        let potion = try fixtureBoons()[3]
        #expect(potion.quantity == 2 && potion.isConsumable && potion.remainingUses == 3)
        let gear = try fixtureBoons()[1]
        #expect(gear.quantity == 1 && !gear.isConsumable && gear.remainingUses == nil)
    }

    @Test func linksResolveAgainstPaizoAndKeyByCharacterAndReward() throws {
        let boon = try fixtureBoons()[0]
        #expect(boon.downloadURL.host == "paizo.com")
        #expect(boon.downloadURL.path.hasSuffix("/wa/downloadBoonPDF"))
        #expect(boon.id == "c1000test1/r200000test")
    }

    @Test func aPageWithoutTheBoonTableHasNoBoons() throws {
        #expect(try BoonsPageParser.boons(in: "<table><tr><th>Other</th></tr></table>", base: base).isEmpty)
    }

    @Test func aBoonWithoutKeysIsKeyedByName() {
        var fields = BoonFields()
        fields.characterName = "Pip"
        fields.name = "Wayfinder"
        #expect(Boon(fields: fields).id == "Pip/Wayfinder")
    }
}

struct BoonLibraryTests {
    @Test func filesGoInAFolderPerCharacterNamedAfterTheBoon() throws {
        let library = BoonLibrary(folder: URL(fileURLWithPath: "/Boons"))
        let urls = library.fileURLs(for: try fixtureBoons())
        #expect(urls["c1000test1/r200001test"]?.path == "/Boons/Valeria Stonebrook/Envoy's Alliance Gear.pdf")
    }

    @Test func boonsWithTheSameNameGetTheirRewardKey() {
        let boons = ["r1", "r2"].map { reward in
            var fields = BoonFields()
            fields.characterName = "Pip"
            fields.name = "Wayfinder"
            fields.downloadURL = URL(string: "https://paizo.com/b?character=c&reward=\(reward)") ?? base
            return Boon(fields: fields)
        }
        let names = Set(BoonLibrary(folder: base).fileURLs(for: boons).values.map(\.lastPathComponent))
        #expect(names == ["Wayfinder (r1).pdf", "Wayfinder (r2).pdf"])
    }

    @Test(arguments: [("A/B: C", "A-B- C"), (" ..Hidden. ", "Hidden"), ("", "Boon")])
    func namesAreSafeForFiles(name: String, expected: String) {
        #expect(BoonLibrary.fileName(name) == expected)
    }

    @Test func savesAndFindsAFile() throws {
        let library = BoonLibrary(folder: temporaryFolder())
        let url = library.folder.appendingPathComponent("Pip/Wayfinder.pdf")
        #expect(!library.hasFile(at: url))
        try library.save(pdfBytes, to: url)
        #expect(library.hasFile(at: url))
        #expect(try Data(contentsOf: url) == pdfBytes)
    }

    @Test func anICloudPlaceholderCountsAsThere() throws {
        let library = BoonLibrary(folder: temporaryFolder(), isInICloud: true)
        let url = library.folder.appendingPathComponent("Pip/Wayfinder.pdf")
        try library.save(Data(), to: url.deletingLastPathComponent().appendingPathComponent(".Wayfinder.pdf.icloud"))
        #expect(library.hasFile(at: url))
    }

    @Test func standardFallsBackToALocalFolderWithoutICloud() async {
        let local = temporaryFolder()
        let library = await BoonLibrary.standard(localFolder: local)
        #expect(!library.isInICloud)
        #expect(library.folder == local.appendingPathComponent("Boons", isDirectory: true))
    }
}

struct BoonRosterTests {
    @Test func boonsGoToTheCharacterTheyName() throws {
        let summaries = try SummaryPageParser.characters(in: Fixture.text("summary"))
        var roster = CharacterRoster(summaries: summaries, sessions: [])
        let named = try fixtureBoons().map { boon -> Boon in
            var fields = BoonFields()
            fields.characterName = boon.characterName == "Someone Else" ? "Nobody" : summaries[0].name
            fields.name = boon.name
            fields.downloadURL = boon.downloadURL
            return Boon(fields: fields)
        }
        roster.attach(named)
        #expect(roster.boons(for: summaries[0].number).count == 4)
        #expect(roster.unmatchedBoons.map(\.characterName) == ["Nobody"])
        #expect(roster.boons(for: summaries[1].number).isEmpty)
    }
}

/// Counts the PDFs it hands out; boons whose reward ends in "locked" have none.
private final class CountingBoonSource: BoonSource, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [String] = []
    var requests: [String] { lock.withLock { asked } }

    func pdf(for boon: Boon) async throws -> Data? {
        lock.withLock { asked.append(boon.id) }
        return boon.id.hasSuffix("locked") ? nil : pdfBytes
    }
}

@MainActor
struct BoonStoreTests {
    private func boon(_ name: String, reward: String) -> Boon {
        var fields = BoonFields()
        fields.characterName = "Valeria Stonebrook"
        fields.name = name
        fields.downloadURL = URL(string: "https://paizo.com/b?character=c1&reward=\(reward)") ?? base
        return Boon(fields: fields)
    }

    private func store(boons: [Boon]) -> CharacterStore {
        let plain = SnapshotFactory.snapshot()
        let snapshot = AccountSnapshot(
            characters: plain.characters, sessions: plain.sessions, boons: boons, fetchedAt: plain.fetchedAt)
        return CharacterStore(repository: InMemoryCharacterRepository()) { snapshot }
    }

    @Test func aRefreshDownloadsEachMissingBoonOnce() async throws {
        let boons = [boon("Wayfinder", reward: "r1"), boon("Secret", reward: "r2locked")]
        let store = store(boons: boons)
        let source = CountingBoonSource()
        await store.useBoonDownloads(BoonDownloads(library: BoonLibrary(folder: temporaryFolder()), source: source))
        await store.refresh()
        #expect(store.boonFiles.keys.sorted() == ["c1/r1"])
        #expect(store.unavailableBoons == ["c1/r2locked"])
        #expect(store.roster.boons(for: "123456-2001").count == 2)
        await store.refresh()
        #expect(source.requests.filter { $0 == "c1/r1" }.count == 1)
    }

    @Test func aPDFAlreadyInTheLibraryIsNotDownloaded() async throws {
        let wayfinder = boon("Wayfinder", reward: "r1")
        let library = BoonLibrary(folder: temporaryFolder())
        try library.save(pdfBytes, to: try #require(library.fileURLs(for: [wayfinder])[wayfinder.id]))
        let store = store(boons: [wayfinder])
        let source = CountingBoonSource()
        await store.refresh()
        await store.useBoonDownloads(BoonDownloads(library: library, source: source))
        #expect(source.requests.isEmpty)
        #expect(store.boonFiles[wayfinder.id] != nil)
    }

    @Test func signingOutForgetsTheBoonFiles() async {
        let store = store(boons: [boon("Wayfinder", reward: "r1")])
        await store.useBoonDownloads(
            BoonDownloads(library: BoonLibrary(folder: temporaryFolder()), source: CountingBoonSource()))
        await store.refresh()
        store.signOut()
        #expect(store.boonFiles.isEmpty && store.roster.characters.isEmpty)
    }
}

struct BoonDownloadTests {
    private func stub(answer: @escaping () -> HTTPResponse) throws -> StubHTTPClient {
        let stub = StubHTTPClient()
        let summary = try Fixture.text("summary"), signIn = try Fixture.text("sign-in")
        stub.on("myAccount/player") { HTTPResponse(data: Data(summary.utf8)) }
        stub.on("DirectAction/signIn") { HTTPResponse(data: Data(signIn.utf8)) }
        stub.on("/ajax/", method: "POST") { HTTPResponse(data: Data("<html></html>".utf8)) }
        stub.on("downloadBoonPDF") { answer() }
        return stub
    }

    @Test func aPDFComesBack() async throws {
        let http = try stub { HTTPResponse(data: pdfBytes) }
        let client = OrganizedPlayClient(http: http, credentials: InMemoryCredentialStore())
        #expect(try await client.pdf(for: fixtureBoons()[1]) == pdfBytes)
    }

    @Test func aPageInsteadOfAPDFMeansNotAvailable() async throws {
        let page = HTTPResponse(data: Data("<html>Must have played it first</html>".utf8))
        let client = OrganizedPlayClient(http: try stub { page }, credentials: InMemoryCredentialStore())
        #expect(try await client.pdf(for: fixtureBoons()[0]) == nil)
    }

    @Test func signsInWhenTheDownloadAsksForAPassword() async throws {
        let signIn = try Fixture.text("sign-in")
        var asked = false
        let stub = try stub {
            defer { asked = true }
            return asked ? HTTPResponse(data: pdfBytes) : HTTPResponse(data: Data(signIn.utf8))
        }
        let account = Credentials(email: "player@example.com", password: "secret")
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore(account))
        #expect(try await client.pdf(for: fixtureBoons()[1]) == pdfBytes)
        #expect(stub.sentRequests.contains { $0.httpMethod == "POST" })
    }

    @Test func aSnapshotSavedBeforeBoonsHasNone() throws {
        let json = #"{"characters":[],"sessions":[],"fetchedAt":"2026-11-18T10:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(AccountSnapshot.self, from: Data(json.utf8)).boons.isEmpty)
    }

    @Test func demoBoonsAreRealPDFsExceptTheLockedOne() async throws {
        let source = DemoBoons.Source()
        let boons = DemoBoons.boons
        #expect(OrganizedPlayClient.isPDF(try #require(await source.pdf(for: boons[0]))))
        #expect(try await source.pdf(for: boons[3]) == nil)
    }
}
