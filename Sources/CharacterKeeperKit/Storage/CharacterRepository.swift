import Foundation

/// Where the app keeps what it has read from the site and what the user has added to it.
public protocol CharacterRepository: Sendable {
    /// The last refresh, or nil before the first one.
    func loadSnapshot() throws -> AccountSnapshot?
    func saveSnapshot(_ snapshot: AccountSnapshot) throws
    /// The user's data keyed by character number; empty before the user has changed anything.
    func loadSettings() throws -> [String: CharacterSettings]
    func saveSettings(_ settings: [String: CharacterSettings]) throws
    /// Forgets the site data, as when signing out. The user's own data stays.
    func deleteSnapshot() throws
    /// The folder the files are in; nil for a repository that keeps nothing on disk.
    var folder: URL? { get }
}

/// What went wrong reading or writing the app's files.
public struct RepositoryError: Error, Equatable, LocalizedError {
    public let operation: String
    public let failure: String

    public var errorDescription: String? { "\(operation) failed: \(failure)" }
}

/// Keeps two JSON files in one folder: `account.json` (site data, replaced on every refresh) and
/// `settings.json` (user data), so a refresh never touches the user's edits.
public struct FileCharacterRepository: CharacterRepository {
    public let directory: URL
    public var folder: URL? { directory }

    public init(folder: URL) {
        directory = folder
    }

    /// `Application Support/Character Keeper`, which is inside the app container on iPad.
    public static func standard() throws -> FileCharacterRepository {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return FileCharacterRepository(folder: support.appendingPathComponent("Character Keeper", isDirectory: true))
    }

    public func loadSnapshot() throws -> AccountSnapshot? {
        try read(AccountSnapshot.self, from: "account.json", operation: "Loading the saved account")
    }

    public func saveSnapshot(_ snapshot: AccountSnapshot) throws {
        try write(snapshot, to: "account.json", operation: "Saving the account")
    }

    public func loadSettings() throws -> [String: CharacterSettings] {
        try read([String: CharacterSettings].self, from: "settings.json", operation: "Loading your settings") ?? [:]
    }

    public func saveSettings(_ settings: [String: CharacterSettings]) throws {
        try write(settings, to: "settings.json", operation: "Saving your settings")
    }

    public func deleteSnapshot() throws {
        let file = directory.appendingPathComponent("account.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { try FileManager.default.removeItem(at: file) } catch {
            throw RepositoryError(operation: "Forgetting the account", failure: error.localizedDescription)
        }
    }

    private func read<Value: Decodable>(_ type: Value.Type, from name: String, operation: String) throws -> Value? {
        let file = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try Self.decoder.decode(type, from: Data(contentsOf: file))
        } catch {
            throw RepositoryError(operation: operation, failure: error.localizedDescription)
        }
    }

    private func write<Value: Encodable>(_ value: Value, to name: String, operation: String) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            throw RepositoryError(operation: operation, failure: error.localizedDescription)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Keeps everything in memory. Used by demo mode and by tests.
/// `@unchecked Sendable`: the values are guarded by `lock`.
public final class InMemoryCharacterRepository: CharacterRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: AccountSnapshot?
    private var settings: [String: CharacterSettings] = [:]

    public init() {}

    public func loadSnapshot() throws -> AccountSnapshot? { lock.withLock { snapshot } }
    public func saveSnapshot(_ snapshot: AccountSnapshot) throws { lock.withLock { self.snapshot = snapshot } }
    public func loadSettings() throws -> [String: CharacterSettings] { lock.withLock { settings } }
    public func saveSettings(_ settings: [String: CharacterSettings]) throws {
        lock.withLock { self.settings = settings }
    }
    public func deleteSnapshot() throws { lock.withLock { snapshot = nil } }
    public var folder: URL? { nil }
}
