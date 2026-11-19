import Foundation
import Testing
@testable import ChronicleKeeperKit

private let chronicleBytes = Data("%PDF-1.4 a chronicle".utf8)

private func temporaryChronicleFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("chronicle-tests-\(UUID().uuidString)")
}

struct ChronicleLibraryTests {
    @Test func filesGoInAFolderPerCharacterNamedAfterTheSession() {
        let library = ChronicleLibrary(folder: URL(fileURLWithPath: "/Chronicles"))
        let url = library.fileURL(characterName: "Drul Goodboy", sessionID: "5235126#2#Drul Goodboy")
        #expect(url.path == "/Chronicles/Drul Goodboy/5235126#2#Drul Goodboy.pdf")
    }

    @Test func savesAndFindsAFile() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let url = library.fileURL(characterName: "Pip", sessionID: "1#1#Pip")
        #expect(!library.hasFile(at: url))
        try library.save(chronicleBytes, to: url)
        #expect(library.hasFile(at: url))
        #expect(try Data(contentsOf: url) == chronicleBytes)
    }

    @Test func anICloudPlaceholderCountsAsThere() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = library.fileURL(characterName: "Pip", sessionID: "1#1#Pip")
        try library.save(Data(), to: ChronicleLibrary.placeholder(of: url))
        #expect(library.hasFile(at: url))
    }

    @Test func onlyAFileWithItsPagesIsOnTheDevice() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = library.fileURL(characterName: "Pip", sessionID: "1#1#Pip")
        try library.save(Data(), to: ChronicleLibrary.placeholder(of: url))
        #expect(!library.isOnDevice(url))
        try library.save(chronicleBytes, to: url)
        #expect(library.isOnDevice(url))
    }

    @Test func waitingForASheetOnTheDeviceReturnsAtOnce() async throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let url = library.fileURL(characterName: "Pip", sessionID: "1#1#Pip")
        try library.save(chronicleBytes, to: url)
        #expect(await library.waitUntilOnDevice(url, timeout: .zero))
    }

    @Test func waitingForASheetEndsWhenItArrives() async throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = library.fileURL(characterName: "Pip", sessionID: "1#1#Pip")
        let arrival = Task {
            try await Task.sleep(for: .milliseconds(100))
            try library.save(chronicleBytes, to: url)
        }
        #expect(await library.waitUntilOnDevice(url, timeout: .seconds(10)))
        try await arrival.value
    }

    @Test func waitingForASheetThatNeverArrivesGivesUp() async {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = library.fileURL(characterName: "Pip", sessionID: "1#1#Pip")
        #expect(!(await library.waitUntilOnDevice(url, timeout: .milliseconds(300))))
    }

    @Test func aCanceledWaitGivesUp() async {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder(), isInICloud: true)
        let url = library.fileURL(characterName: "Pip", sessionID: "1#1#Pip")
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
        let url = library.fileURL(characterName: "Pip", sessionID: "1#1#Pip")
        try library.remove(at: url)
    }

    @Test func savedFileCanBeRemoved() throws {
        let library = ChronicleLibrary(folder: temporaryChronicleFolder())
        let url = library.fileURL(characterName: "Pip", sessionID: "1#1#Pip")
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
