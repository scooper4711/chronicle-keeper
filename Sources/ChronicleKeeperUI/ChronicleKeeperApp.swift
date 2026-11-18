import AppNotices
import ChronicleKeeperKit
import SwiftUI

/// The app, shared by the Mac and the iPad.
public struct ChronicleKeeperApp: App {
    @State private var session: AccountSession

    public init() {
        let session = AccountSession(live: .standard())
        // `-demo` opens on the demo account, for UI tests and screenshots.
        if ProcessInfo.processInfo.arguments.contains("-demo") { session.startDemo() }
        _session = State(initialValue: session)
    }

    private let portraits = PortraitStore.forApp()

    public var body: some Scene {
        WindowGroup("Chronicle Keeper") {
            MainWindow()
                .environment(session)
                .environment(\.portraits, portraits)
                .task { await session.startSync(portraits: portraits) }
                .task { await session.startBoons() }
            #if os(macOS)
                .frame(minWidth: 860, minHeight: 520)
            #endif
        }
        .commands {
            AccountCommands(session: session)
            AboutCommands(info: .chronicleKeeper)
        }
        #if os(iOS)
        AboutWindow(info: .chronicleKeeper)
        #endif
    }
}

extension AboutInfo {
    // A literal URL that is known to parse.
    // swiftlint:disable:next force_unwrapping
    static let contactURL = URL(string: "https://github.com/scooper4711/chronicle-keeper/issues")!

    static let chronicleKeeper = AboutInfo(
        appName: "Chronicle Keeper",
        tagline: "Keeps track of your Pathfinder Society and Starfinder Society characters: adventures, reputation, "
            + "XP and level, read from your My Organized Play page on paizo.com.",
        credits: [],
        contactURL: contactURL)
}

extension AccountSession.LiveAccount {
    /// The real paizo.com, the Keychain and the app's files.
    @MainActor
    static func standard() -> AccountSession.LiveAccount {
        let credentials = KeychainCredentialStore()
        let repository: CharacterRepository = (try? FileCharacterRepository.standard())
            ?? FileCharacterRepository(folder: FileManager.default.temporaryDirectory
                .appendingPathComponent("Chronicle Keeper", isDirectory: true))
        return AccountSession.LiveAccount(
            client: OrganizedPlayClient(http: URLSessionHTTPClient(), credentials: credentials),
            credentials: credentials, repository: repository)
    }
}

extension PortraitStore {
    static func forApp() -> PortraitStore {
        (try? standard()) ?? PortraitStore(
            folder: FileManager.default.temporaryDirectory.appendingPathComponent("Portraits", isDirectory: true))
    }
}

extension EnvironmentValues {
    @Entry var portraits = PortraitStore(
        folder: FileManager.default.temporaryDirectory.appendingPathComponent("Portraits", isDirectory: true))
}

/// The Account menu: refresh, the adventure finder, and signing out or leaving the demo.
struct AccountCommands: Commands {
    let session: AccountSession
    @FocusedValue(\.showsFinder) private var showsFinder

    var body: some Commands {
        CommandMenu("Account") {
            Button("Refresh") { Task { await session.store.refresh() } }
                .keyboardShortcut("r")
                .disabled(!session.canRefresh)
            Button("Who Can Play…") { showsFinder?.wrappedValue = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(showsFinder == nil || session.mode == .signedOut)
            Divider()
            if session.isDemo {
                Button("Leave the Demo") { session.leaveDemo() }
            } else {
                Button("Sign Out") { session.signOut() }
                    .disabled(session.mode == .signedOut)
            }
        }
    }
}

extension FocusedValues {
    @Entry var showsFinder: Binding<Bool>?
}
