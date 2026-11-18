#if os(iOS)
import AppNotices
import CharacterKeeperKit
import SwiftUI

/// The iPhone and iPad stand-in for the Mac's Account and Help menus: About, and signing out or leaving the demo.
struct AccountMenu: View {
    @Environment(AccountSession.self) private var session
    @State private var showsAbout = false

    var body: some View {
        Menu {
            Button { showsAbout = true } label: { Label("About Character Keeper", systemImage: "info.circle") }
            Divider()
            if session.isDemo {
                Button { session.leaveDemo() } label: {
                    Label("Leave the Demo", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button(role: .destructive) { session.signOut() } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
        .sheet(isPresented: $showsAbout) { AboutSheet(info: .characterKeeper) }
    }
}
#endif
