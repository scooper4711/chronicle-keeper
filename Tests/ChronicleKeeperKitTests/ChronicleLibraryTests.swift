import Foundation
import Testing
@testable import ChronicleKeeperKit

private let chronicleBytes = Data("%PDF-1.4 a chronicle".utf8)

private func temporaryChronicleFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("chronicle-tests-\(UUID().uuidString)")
}

/// Where the fixture session's sheet goes now.
private func sheet(in library: ChronicleLibrary) -> URL {
    library.fileURL(characterNumber: "123456-2001", session: SessionFactory.session())
}

/// Saves a sheet where 1.0.0 put it, under the character's name at the time.
private func saveNamedSheet(in library: ChronicleLibrary, name: String = "PF Coop 333") throws -> URL {
    let url = library.folder.appendingPathComponent("\(name)/1234#1#\(name).pdf")
    try library.save(chronicleBytes, to: url)
    return url
}

struct ChronicleLibraryTests {
    @Test func filesGoInAFolderPerCharacterNumberNamedAfterTheSession() {
        let library = ChronicleLibrary(folder: URL(fileURLWithPath: "/Chronicles"))
        let session = SessionFactory.session(sessionNumber: 2, eventCode: "5235126", characterName: "Drul Goodboy")
        let url = library.fileURL(characterNumber: "123456-2001", session: session)
        #expect(url.path == "/Chronicles/123456-2001/5235126#2.pdf")
    }

    @Test func findsSheetsFiledByNameWhateverTheCharacterIsCalledNow() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let named = try saveNamedSheet(in: library)
        try library.save(chronicleBytes, to: sheet(in: library))
        #expect(library.namedFiles() == ["1234#1": named])
    }

    @Test func findsAnICloudPlaceholderOfASheetFiledByName() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let named = library.folder.appendingPathComponent("Pip/1234#1#Pip.pdf")
        try library.save(Data(), to: ChronicleLibrary.placeholder(of: named))
        #expect(library.namedFiles() == ["1234#1": named])
    }

    @Test func prefersTheOriginalToAnICloudConflictCopy() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let original = try saveNamedSheet(in: library)
        try library.save(chronicleBytes, to: original.deletingLastPathComponent()
            .appendingPathComponent("1234#1#PF Coop 333 2.pdf"))
        #expect(library.namedFiles() == ["1234#1": original])
    }

    /// A sheet whose session paizo.com doesn't list yet waits in the pending folder (R1.14).
    @Test func anUnreportedSheetGoesInThePendingFolder() {
        let library = ChronicleLibrary(folder: URL(fileURLWithPath: "/Chronicles"))
        let url = library.fileURL(characterNumber: "123456-2001", session: UnreportedFactory.newSheet("a-b"))
        #expect(url.path == "/Chronicles/Pending/123456-2001/a-b.pdf")
        #expect(library.pendingURL(ChronicleLibrary.pendingFile(characterNumber: "123456-2001", id: "a-b")) == url)
    }

    @Test func pendingSheetsAreNotTakenForSheetsFiledByName() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        try library.save(chronicleBytes, to: library.pendingURL("123456-2001/a"))
        try library.save(chronicleBytes, to: library.pendingURL("123456-2001/1234#1#Pip"))
        #expect(library.namedFiles().isEmpty)
    }

    @Test func adoptingAPendingSheetMovesItToItsSessionAndTidiesItsFolder() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let pending = library.pendingURL("123456-2001/a")
        try library.save(chronicleBytes, to: pending)
        let url = sheet(in: library)
        #expect(library.adopt(pending, to: url) == url)
        #expect(try Data(contentsOf: url) == chronicleBytes)
        #expect(!FileManager.default.fileExists(atPath: pending.deletingLastPathComponent().path))
    }

    @Test func aPendingSheetThatIsOnlyInICloudStaysPending() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let pending = library.pendingURL("123456-2001/a")
        try library.save(Data(), to: ChronicleLibrary.placeholder(of: pending))
        #expect(library.adopt(pending, to: sheet(in: library)) == pending)
        #expect(library.hasFile(at: pending))
    }

    @Test func aMissingLibraryHasNoNamedSheets() {
        #expect(ChronicleLibrary(folder: temporaryChronicleFolder()).namedFiles().isEmpty)
    }

    @Test func movesASheetFiledByNameAndTidiesItsFolder() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let named = try saveNamedSheet(in: library)
        let url = sheet(in: library)
        #expect(library.moveNamedFile(named, to: url) == url)
        #expect(try Data(contentsOf: url) == chronicleBytes)
        #expect(!FileManager.default.fileExists(atPath: named.deletingLastPathComponent().path))
    }

    @Test func leavesASheetFiledByNameThatIsOnlyInICloud() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let named = library.folder.appendingPathComponent("Pip/1234#1#Pip.pdf")
        try library.save(Data(), to: ChronicleLibrary.placeholder(of: named))
        #expect(library.moveNamedFile(named, to: sheet(in: library)) == named)
    }

    @Test func leavesASheetFiledByNameThatCantBeMoved() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let named = try saveNamedSheet(in: library)
        // A file where the new folder would go stops the move.
        let blocked = library.folder.appendingPathComponent("blocked")
        try library.save(chronicleBytes, to: blocked)
        #expect(library.moveNamedFile(named, to: blocked.appendingPathComponent("1234#1.pdf")) == named)
        #expect(library.hasFile(at: named))
    }

    @Test func savesAndFindsAFile() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let url = sheet(in: library)
        #expect(!library.hasFile(at: url))
        try library.save(chronicleBytes, to: url)
        #expect(library.hasFile(at: url))
        #expect(try Data(contentsOf: url) == chronicleBytes)
    }

    @Test func anICloudPlaceholderCountsAsThere() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = sheet(in: library)
        try library.save(Data(), to: ChronicleLibrary.placeholder(of: url))
        #expect(library.hasFile(at: url))
    }

    @Test func onlyAFileWithItsPagesIsOnTheDevice() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = sheet(in: library)
        try library.save(Data(), to: ChronicleLibrary.placeholder(of: url))
        #expect(!library.isOnDevice(url))
        try library.save(chronicleBytes, to: url)
        #expect(library.isOnDevice(url))
    }

    @Test func waitingForASheetOnTheDeviceReturnsAtOnce() async throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let url = sheet(in: library)
        try library.save(chronicleBytes, to: url)
        #expect(await library.waitUntilOnDevice(url, timeout: .zero))
    }

    @Test func waitingForASheetEndsWhenItArrives() async throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = sheet(in: library)
        let arrival = Task {
            try await Task.sleep(for: .milliseconds(100))
            try library.save(chronicleBytes, to: url)
        }
        #expect(await library.waitUntilOnDevice(url, timeout: .seconds(10)))
        try await arrival.value
    }

    @Test func waitingForASheetThatNeverArrivesGivesUp() async {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = sheet(in: library)
        #expect(!(await library.waitUntilOnDevice(url, timeout: .milliseconds(300))))
    }

    @Test func aCanceledWaitGivesUp() async {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = sheet(in: library)
        let wait = Task { await library.waitUntilOnDevice(url, timeout: .seconds(30)) }
        wait.cancel()
        #expect(!(await wait.value))
    }

    @Test func aBoonLibraryBringsItsPDFsDownTheSameWay() async throws {
        let library = BoonLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = library.folder.appendingPathComponent("Pip/Boon.pdf")
        try library.save(Data(), to: BoonLibrary.placeholder(of: url))
        #expect(library.hasFile(at: url))
        #expect(!library.isOnDevice(url))
        #expect(!(await library.waitUntilOnDevice(url, timeout: .milliseconds(300))))
        try library.save(chronicleBytes, to: url)
        #expect(await library.waitUntilOnDevice(url, timeout: .zero))
    }

    @Test func removingAMissingFileDoesNothing() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let url = sheet(in: library)
        try library.remove(at: url)
    }

    @Test func savedFileCanBeRemoved() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let url = sheet(in: library)
        try library.save(chronicleBytes, to: url)
        try library.remove(at: url)
        #expect(!library.hasFile(at: url))
    }

    @Test func standardFallsBackToALocalFolderWithoutICloud() async {
        let local = temporaryChronicleFolder()
        let library = await ChronicleLibrary.standard(localFolder: local)
        #expect(!library.isInICloud)
        #expect(library.folder == local.appendingPathComponent("Chronicles", isDirectory: true))
    }

    @Test(arguments: [("A/B: C", "A-B- C"), (" ..Hidden. ", "Hidden"), ("", "File")])
    func namesAreSafeForFiles(name: String, expected: String) {
        #expect(DocumentFileName.of(name) == expected)
    }
}
