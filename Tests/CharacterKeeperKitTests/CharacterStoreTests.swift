import Foundation
import Testing
@testable import CharacterKeeperKit

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
        let store = store(repository) { throw OrganizedPlayError.signInRejected }
        store.load()
        await store.refresh()
        #expect(store.roster.characters.count == 1)
        #expect(store.errorMessage == OrganizedPlayError.signInRejected.errorDescription)
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
        first.update(number) { $0.xpAdjustment = 2 }
        let second = store(repository) { SnapshotFactory.snapshot() }
        second.load()
        #expect(second.settings(for: number).xpAdjustment == 2)
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
            .appendingPathComponent("character-keeper-tests-\(UUID().uuidString)")
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
            .appendingPathComponent("character-keeper-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appendingPathComponent("account.json"))
        return folder
    }
}
