import Foundation
import Testing
@testable import ChronicleKeeperKit

@MainActor
struct CharacterStoreTests {
    private let number = "123456-2001"

    private func snapshot() -> AccountSnapshot { SnapshotFactory.snapshot() }

    private func store(
        _ repository: CharacterRepository = InMemoryCharacterRepository(),
        fetch: @escaping @Sendable () async throws -> AccountSnapshot
    ) -> CharacterStore {
        CharacterStore(repository: repository, fetchAccount: fetch)
    }

    @Test func refreshBuildsTheRosterAndSavesTheSnapshot() async throws {
        let repository = InMemoryCharacterRepository()
        let fresh = snapshot()
        let store = store(repository) { fresh }
        await store.refresh()
        #expect(store.roster.characters.count == 1)
        #expect(store.lastRefresh == fresh.fetchedAt)
        #expect(try repository.loadSnapshot()?.characters.count == 1)
    }

    @Test func loadShowsTheSavedSnapshotWithoutFetching() throws {
        let repository = InMemoryCharacterRepository()
        try repository.saveSnapshot(snapshot())
        let store = store(repository) { throw OrganizedPlayError.noCredentials }
        store.load()
        #expect(store.roster.characters.count == 1)
        #expect(store.errorMessage == nil)
    }

    @Test func aFailedRefreshKeepsTheSavedData() async throws {
        let repository = InMemoryCharacterRepository()
        try repository.saveSnapshot(snapshot())
        let store = store(repository) { throw OrganizedPlayError.noCredentials }
        store.load()
        await store.refresh()
        #expect(store.roster.characters.count == 1)
        #expect(store.errorMessage == OrganizedPlayError.noCredentials.errorDescription)
        #expect(!store.isRefreshing)
    }

    @Test func userSettingsSurviveARefresh() async throws {
        let fresh = snapshot()
        let store = store { fresh }
        await store.refresh()
        store.update(number) { $0.defaultTrack = .slow; $0.notes = "Level 5 by Gen Con" }
        await store.refresh()
        #expect(store.settings(for: number).defaultTrack == .slow)
        #expect(store.roster.characters[0].settings.notes == "Level 5 by Gen Con")
    }

    @Test func settingsAreSavedAndLoadedAgain() throws {
        let repository = InMemoryCharacterRepository()
        let first = store(repository) { SnapshotFactory.snapshot() }
        first.update(number) { $0.startingLevel = 3 }
        let second = store(repository) { SnapshotFactory.snapshot() }
        second.load()
        #expect(second.settings(for: number).startingLevel == 3)
    }

    @Test func signOutForgetsSiteDataButKeepsSettings() async throws {
        let fresh = snapshot()
        let store = store { fresh }
        await store.refresh()
        store.update(number) { $0.notes = "keep me" }
        store.signOut()
        #expect(store.roster.characters.isEmpty)
        #expect(store.lastRefresh == nil)
        #expect(store.settings(for: number).notes == "keep me")
    }

    @Test func unknownCharactersGetDefaultSettings() {
        let store = store { SnapshotFactory.snapshot() }
        #expect(store.settings(for: "nobody") == CharacterSettings())
    }

    private func chronicleFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("chronicle-store-tests-\(UUID().uuidString)")
    }

    private let session = SessionFactory.session()
    private let sheet = Data("%PDF-1.4".utf8)

    @Test func attachingAChronicleSavesItAndFindsItAgain() async throws {
        let original = store { SnapshotFactory.snapshot() }
        await original.refresh()
        let folder = chronicleFolder()
        original.useChronicleLibrary(ChronicleLibrary(folder: folder))
        original.attachChronicle(sheet, to: session, characterNumber: number)
        #expect(original.errorMessage == nil)
        #expect(original.chronicleFiles[session.id] != nil)

        // A fresh store, pointed at the same library, finds the file that's already there.
        let again = store { SnapshotFactory.snapshot() }
        await again.refresh()
        again.useChronicleLibrary(ChronicleLibrary(folder: folder))
        #expect(again.chronicleFiles[session.id] != nil)
    }

    @Test func aRenamedCharacterKeepsTheSheetsAttachedUnderItsOldName() async throws {
        let library = ChronicleLibrary(folder: chronicleFolder())
        let oldName = "PF Coop 333"
        let named = library.folder.appendingPathComponent("\(oldName)/1234#1#\(oldName).pdf")
        try library.save(sheet, to: named)
        let store = store { SnapshotFactory.snapshot() }
        await store.refresh()
        store.useChronicleLibrary(library)
        let url = try #require(store.chronicleFiles[session.id])
        #expect(url == library.fileURL(characterNumber: number, session: session))
        #expect(try Data(contentsOf: url) == sheet)
    }

    @Test func attachingInPlaceOfASheetFiledByNameRemovesIt() async throws {
        let library = ChronicleLibrary(folder: chronicleFolder(), isInICloud: true)
        let named = library.folder.appendingPathComponent("Old Name/1234#1#Old Name.pdf")
        try library.save(Data(), to: ChronicleLibrary.placeholder(of: named))
        let store = store { SnapshotFactory.snapshot() }
        await store.refresh()
        store.useChronicleLibrary(library)
        #expect(store.chronicleFiles[session.id] == named)
        store.attachChronicle(sheet, to: session, characterNumber: number)
        #expect(store.chronicleFiles[session.id] == library.fileURL(characterNumber: number, session: session))
    }

    @Test func anEarlierFailureDoesntStopASheetBeingAttachedOrRemoved() async throws {
        let store = store { throw URLError(.notConnectedToInternet) }
        await store.refresh()
        #expect(store.errorMessage != nil)
        store.useChronicleLibrary(ChronicleLibrary(folder: chronicleFolder()))
        store.attachChronicle(sheet, to: session, characterNumber: number)
        #expect(store.chronicleFiles[session.id] != nil)
        store.removeChronicle(from: session, characterNumber: number)
        #expect(store.chronicleFiles[session.id] == nil)
    }

    @Test func removingAChronicleForgetsIt() async throws {
        let store = store { SnapshotFactory.snapshot() }
        await store.refresh()
        store.useChronicleLibrary(ChronicleLibrary(folder: chronicleFolder()))
        store.attachChronicle(sheet, to: session, characterNumber: number)
        store.removeChronicle(from: session, characterNumber: number)
        #expect(store.chronicleFiles[session.id] == nil)
    }

    @Test func signingOutForgetsTheChronicleFiles() async throws {
        let store = store { SnapshotFactory.snapshot() }
        await store.refresh()
        store.useChronicleLibrary(ChronicleLibrary(folder: chronicleFolder()))
        store.attachChronicle(sheet, to: session, characterNumber: number)
        store.signOut()
        #expect(store.chronicleFiles.isEmpty)
    }
}

enum SnapshotFactory {
    static func snapshot() -> AccountSnapshot {
        let summary = CharacterSummary(
            number: "123456-2001", campaign: .pathfinder2, name: "Valeria Stonebrook", factions: [], standing: [])
        return AccountSnapshot(
            characters: [summary], sessions: [SessionFactory.session()],
            fetchedAt: Date(timeIntervalSince1970: 1_780_000_000))
    }
}

struct FileCharacterRepositoryTests {
    private func repository() -> FileCharacterRepository {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-keeper-tests-\(UUID().uuidString)")
        return FileCharacterRepository(folder: folder)
    }

    private let snapshot = AccountSnapshot(
        characters: [CharacterSummary(
            number: "123456-2001", campaign: .starfinder2, name: "Sunny", factions: [], standing: [])],
        sessions: [SessionFactory.session()], fetchedAt: Date(timeIntervalSince1970: 1_780_000_000))

    @Test func startsEmpty() throws {
        let repository = repository()
        #expect(try repository.loadSnapshot() == nil)
        #expect(try repository.loadSettings().isEmpty)
    }

    @Test func roundTripsTheSnapshot() throws {
        let repository = repository()
        try repository.saveSnapshot(snapshot)
        let loaded = try #require(try repository.loadSnapshot())
        #expect(loaded.characters == snapshot.characters)
        #expect(loaded.sessions == snapshot.sessions)
        #expect(loaded.fetchedAt == snapshot.fetchedAt)
    }

    @Test func roundTripsTheSettings() throws {
        let repository = repository()
        var settings = CharacterSettings(defaultTrack: .slow)
        settings.overrides["1234#1"] = SessionOverride(track: .slow, xp: 2)
        settings.characterSheetLink = "https://example.com/sheet"
        try repository.saveSettings(["123456-2001": settings])
        #expect(try repository.loadSettings() == ["123456-2001": settings])
    }

    @Test func deletingTheSnapshotKeepsTheSettings() throws {
        let repository = repository()
        try repository.saveSnapshot(snapshot)
        try repository.saveSettings(["x": CharacterSettings(notes: "n")])
        try repository.deleteSnapshot()
        try repository.deleteSnapshot()
        #expect(try repository.loadSnapshot() == nil)
        #expect(try repository.loadSettings()["x"]?.notes == "n")
    }

    @Test func aCorruptFileSaysWhichOperationFailed() throws {
        let corrupt = FileCharacterRepository(folder: try corruptFolder())
        #expect(throws: RepositoryError.self) { try corrupt.loadSnapshot() }
    }

    private func corruptFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-keeper-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appendingPathComponent("account.json"))
        return folder
    }
}

/// A file of the user's data that can't be read must never be saved over, nor its loss synced (code review).
@MainActor
struct UnreadableSettingsTests {
    private let number = "123456-2001"
    private let broken = Data(#"{"123456-2001":{"earned":"not a dictionary"}}"#.utf8)

    private func storeWithUnreadableLedger() throws -> (CharacterStore, FileCharacterRepository) {
        let repository = FileCharacterRepository(folder: FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-store-unreadable-\(UUID().uuidString)"))
        try repository.saveSettings([number: CharacterSettings(notes: "keep me")])
        try broken.write(to: repository.directory.appendingPathComponent("wealth.json"))
        let store = CharacterStore(repository: repository) { SnapshotFactory.snapshot() }
        store.load()
        return (store, repository)
    }

    @Test func anUnreadableLedgerStopsSavingAndSays() throws {
        let (store, _) = try storeWithUnreadableLedger()
        #expect(!store.canSaveSettings)
        #expect(store.errorMessage?.contains("aren't saved") == true)
    }

    @Test func anEditLeavesBothFilesAsTheyWere() throws {
        let (store, repository) = try storeWithUnreadableLedger()
        let settingsFile = repository.directory.appendingPathComponent("settings.json")
        let before = try Data(contentsOf: settingsFile)
        var reported: [String] = []
        store.onLocalChange = { reported.append($0) }
        store.update(number) { $0.notes = "overwritten" }
        #expect(try Data(contentsOf: settingsFile) == before)
        #expect(try Data(contentsOf: repository.directory.appendingPathComponent("wealth.json")) == broken)
        #expect(reported.isEmpty)
    }

    @Test func remoteChangesWaitToo() throws {
        let (store, repository) = try storeWithUnreadableLedger()
        let settingsFile = repository.directory.appendingPathComponent("settings.json")
        let before = try Data(contentsOf: settingsFile)
        store.applyRemote([number: CharacterSettings(notes: "from another device")])
        #expect(try Data(contentsOf: settingsFile) == before)
    }
}
