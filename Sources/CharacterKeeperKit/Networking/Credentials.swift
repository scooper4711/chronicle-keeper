import Foundation
import Security

public struct Credentials: Sendable, Equatable {
    public var email: String
    public var password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }

    public var isComplete: Bool { !email.isEmpty && !password.isEmpty }
}

/// Where the Paizo account is kept between launches.
public protocol CredentialStore: Sendable {
    func load() -> Credentials?
    func save(_ credentials: Credentials) throws
    func delete() throws
}

/// Keeps the account in memory only. Used by demo mode and by tests.
/// `@unchecked Sendable`: the account is guarded by `lock`.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Credentials?

    public init(_ credentials: Credentials? = nil) {
        stored = credentials
    }

    public func load() -> Credentials? { lock.withLock { stored } }

    public func save(_ credentials: Credentials) throws { lock.withLock { stored = credentials } }

    public func delete() throws { lock.withLock { stored = nil } }
}

public struct KeychainError: Error, Equatable, LocalizedError {
    public let operation: String
    public let status: OSStatus

    public var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
        return "\(operation) failed: \(detail)"
    }
}

/// Keeps the account as one internet-password item for paizo.com, the kind of item Safari saves, so it
/// appears in the Passwords app and syncs with iCloud Keychain. That needs the data-protection keychain,
/// which only a properly signed app may use; an ad hoc build falls back to the login keychain.
public struct KeychainCredentialStore: CredentialStore {
    private let server: String

    public init(server: String = "paizo.com") {
        self.server = server
    }

    public func load() -> Credentials? {
        for keychain in Keychain.allCases {
            if let credentials = load(from: keychain) { return credentials }
        }
        return nil
    }

    public func save(_ credentials: Credentials) throws {
        try delete()
        let status = add(credentials, to: .iCloud)
        if status == errSecMissingEntitlement {
            let fallback = add(credentials, to: .login)
            guard fallback == errSecSuccess else { throw saveError(fallback) }
            return
        }
        guard status == errSecSuccess else { throw saveError(status) }
    }

    public func delete() throws {
        for keychain in Keychain.allCases {
            let status = SecItemDelete(query(keychain) as CFDictionary)
            let ignorable: Set<OSStatus> = [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement]
            guard ignorable.contains(status) else {
                throw KeychainError(operation: "Removing the paizo.com password from the Keychain", status: status)
            }
        }
    }

    // MARK: - Keychain items

    private enum Keychain: CaseIterable {
        /// The data-protection keychain, synced with iCloud Keychain and shown in Passwords.
        case iCloud
        /// The file-based login keychain, for ad hoc builds.
        case login
    }

    private func load(from keychain: Keychain) -> Credentials? {
        var search = query(keychain)
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        search[kSecReturnAttributes as String] = true
        search[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let email = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return Credentials(email: email, password: password)
    }

    private func add(_ credentials: Credentials, to keychain: Keychain) -> OSStatus {
        var attributes = query(keychain)
        attributes[kSecAttrAccount as String] = credentials.email
        attributes[kSecValueData as String] = Data(credentials.password.utf8)
        attributes[kSecAttrSynchronizable as String] = keychain == .iCloud
        attributes[kSecAttrLabel as String] = server
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    private func query(_ keychain: Keychain) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain as String: keychain == .iCloud
        ]
    }

    private func saveError(_ status: OSStatus) -> KeychainError {
        KeychainError(operation: "Saving the paizo.com password to the Keychain", status: status)
    }
}
