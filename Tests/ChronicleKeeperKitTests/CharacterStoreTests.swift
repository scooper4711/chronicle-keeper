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

    @Test func attachingAChronicleSavesItAndFindsItAgain() async throws {
        let original = store { SnapshotFactory.snapshot() }
        await original.refresh()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-store-tests-\(UUID().uuidString)")
        original.useChronicleLibrary(ChronicleLibrary(folder: folder))
        let sessionID = "1234#1#Valeria Stonebrook"
        original.attachChronicle(Data("%PDF-1.4".utf8), to: sessionID, characterName: "Valeria Stonebrook")
        #expect(original.errorMessage == nil)
        #expect(original.chronicleFiles[sessionID] != nil)

        // A fresh store, pointed at the same library, finds the file that's already there.
        let again = store { SnapshotFactory.snapshot() }
        await again.refresh()
        again.useChronicleLibrary(ChronicleLibrary(folder: folder))
        #expect(again.chronicleFiles[sessionID] != nil)
    }

    @Test func removingAChronicleForgetsIt() async throws {
        let store = store { SnapshotFactory.snapshot() }
        await store.refresh()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-store-tests-\(UUID().uuidString)")
        store.useChronicleLibrary(ChronicleLibrary(folder: folder))
        let sessionID = "1234#1#Valeria Stonebrook"
        store.attachChronicle(Data("%PDF-1.4".utf8), to: sessionID, characterName: "Valeria Stonebrook")
        store.removeChronicle(from: sessionID, characterName: "Valeria Stonebrook")
        #expect(store.chronicleFiles[sessionID] == nil)
    }

    @Test func signingOutForgetsTheChronicleFiles() async throws {
        let store = store { SnapshotFactory.snapshot() }
        await store.refresh()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-store-tests-\(UUID().uuidString)")
        store.useChronicleLibrary(ChronicleLibrary(folder: folder))
        store.attachChronicle(
            Data("%PDF-1.4".utf8), to: "1234#1#Valeria Stonebrook", characterName: "Valeria Stonebrook")
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
        settings.overrides["1234#1#Sunny"] = SessionOverride(track: .slow, xp: 2)
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
