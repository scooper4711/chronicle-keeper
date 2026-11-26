import ChronicleKeeperKit
import SwiftUI

/// Marks a session paizo.com doesn't list yet (R1.14): a clock in a capsule, with the word beside it unless it is
/// compact. It says so to VoiceOver and on a hover, so color is never the only signal.
struct UnreportedBadge: View {
    var isCompact = false
    /// What it says in full; the sidebar's says how many sessions.
    var help = UnreportedText.badgeHelp

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
            if !isCompact { Text(UnreportedText.badge) }
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(Color.unreported)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.unreported.opacity(0.15), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isCompact ? help : UnreportedText.badge)
        .accessibilityHint(isCompact ? "" : help)
        .accessibilityIdentifier("unreported-badge")
        .help(help)
    }
}

extension Color {
    /// The color of what paizo.com doesn't list yet, where reported adventures use the tint.
    static let unreported = Color.orange
}

/// At the top of an unreported session's details: where its numbers come from.
struct UnreportedBanner: View {
    var body: some View {
        Label(UnreportedText.banner, systemImage: "clock")
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.unreported.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("unreported-banner")
    }
}

/// "Add Chronicle…" in the adventures section's title: a sheet for a session paizo.com doesn't list yet, scanned
/// or attached and confirmed like any other (R1.14).
struct AddChronicleMenu: View {
    let record: CharacterRecord
    let store: CharacterStore
    var isCompact = false
    /// Names the sheet that would be added. A new one is made once this one was kept.
    @State private var id = UUID().uuidString

    var body: some View {
        let session = UnreportedSheet.session(id: id, reading: SheetReading(), for: record.summary)
        ChronicleMenu(sheet: SessionSheet(session: session, record: record, store: store)) { _ in
            if isCompact {
                Label("Add Chronicle…", systemImage: "doc.badge.plus").labelStyle(.iconOnly)
            } else {
                Label("Add Chronicle…", systemImage: "doc.badge.plus")
            }
        }
        .menuStyle(.button).buttonStyle(.bordered).fixedSize()
        .help("Add the chronicle sheet of a session paizo.com doesn't list yet")
        .accessibilityIdentifier("add-chronicle")
        .onChange(of: record.settings.wealth.sheetReadings.count) { id = UUID().uuidString }
    }
}

/// Asks what to do with an unreported sheet the user removes (R1.14): delete it, or attach it to an adventure
/// paizo.com does list, which keeps its gold, corrections and purchases.
struct UnreportedRemoval: ViewModifier {
    let sheet: SessionSheet
    @Binding var isAsking: Bool
    @State private var choosesAdventure = false

    func body(content: Content) -> some View {
        // Every row's menu has this modifier: the adventures are looked up only once the user is asked.
        let candidates = isAsking || choosesAdventure ? sheet.sessionsWithoutSheet : []
        content
            .confirmationDialog("Remove This Chronicle?", isPresented: $isAsking, titleVisibility: .visible) {
                Button("Delete the Chronicle", role: .destructive) { sheet.delete() }
                if !candidates.isEmpty {
                    Button("Attach to Another Adventure…") { choosesAdventure = true }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(UnreportedText.removalMessage(
                    purchases: sheet.purchasesAfter, canAttach: !candidates.isEmpty))
            }
            .sheet(isPresented: $choosesAdventure) { AdventureChooser(sheet: sheet, candidates: candidates) }
    }
}

/// The character's reported adventures that have no chronicle sheet, to attach an unreported sheet to one.
struct AdventureChooser: View {
    let sheet: SessionSheet
    let candidates: [SessionProgress]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates) { progress in
                Button {
                    sheet.attach(to: progress.session)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progress.session.adventure.titleWithLevels).multilineTextAlignment(.leading)
                        Text(SessionDateText.day(progress.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Attach the Chronicle To")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }
}

/// Under an unreported sheet: its session seems to be reported for another of the user's characters. Nothing
/// moves on its own; the user moves the sheet, or keeps waiting for a corrected report (R1.15).
struct SheetElsewhereRow: View {
    let match: PendingSheetMatcher.Match
    let sheet: SessionSheet

    var body: some View {
        let name = sheet.store.roster.characters.first { $0.id == match.to }?.name ?? match.to
        VStack(alignment: .leading, spacing: 6) {
            SheetWarningText(
                text: UnreportedText.elsewhere(adventure: match.session.adventure.title, character: name))
            HStack(spacing: 8) {
                Button("Move to \(name)") { sheet.store.attach(match) }
                Button("Keep Waiting") { sheet.keepWaiting(match) }
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Asks before an unreported sheet is removed, when `isAsking` is set.
    func unreportedRemoval(of sheet: SessionSheet, isAsking: Binding<Bool>) -> some View {
        modifier(UnreportedRemoval(sheet: sheet, isAsking: isAsking))
    }
}
