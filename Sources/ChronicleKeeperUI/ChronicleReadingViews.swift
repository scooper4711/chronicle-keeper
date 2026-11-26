import ChronicleKeeperKit
import SwiftUI

/// A PDF that waits for the user's confirmation as a session's chronicle sheet.
struct SheetCandidate: Identifiable {
    let id = UUID()
    let pdf: Data
    /// Whether it is the sheet the session already has, being read again: its file is saved only when turned.
    var isAttached = false
}

/// One screen that confirms the picture and what was read from it, with one button (R1.11): the page, which the
/// user can zoom and turn, beside the character number, the XP and the gold, filled with what was read. Text
/// recognition misreads handwriting with full confidence, so nothing read is used before the user has seen it
/// here; a value that disagrees with paizo.com's record says so, so a misread is corrected before it is a warning.
/// A sheet added ahead of its report (R1.14) also asks for its scenario number and the day it was played.
struct SheetConfirmation: View {
    let candidate: SheetCandidate
    let sheet: SessionSheet
    @Environment(\.dismiss) private var dismiss
    @State private var pdf: Data
    /// How far the user has turned the page, in quarter turns clockwise (0 to 3); each turn reads the sheet again.
    @State private var turns = 0
    /// What was read; nil while the sheet is being read.
    @State private var located: LocatedReading?
    @State private var draft: SheetDraft

    /// Under this width the fields go below the page, as on an iPhone.
    private static let sideBySideWidth: CGFloat = 640

    init(candidate: SheetCandidate, sheet: SessionSheet) {
        self.candidate = candidate
        self.sheet = sheet
        _pdf = State(initialValue: candidate.pdf)
        _draft = State(initialValue: SheetDraft(reading: SheetReading(), currency: sheet.currency))
    }

    private var session: PlayedSession { sheet.session }
    private var record: CharacterRecord { sheet.record }
    private var store: CharacterStore { sheet.store }
    private var currency: Currency { sheet.currency }

    var body: some View {
        NavigationStack {
            GeometryReader { space in
                if space.size.width >= Self.sideBySideWidth {
                    HStack(spacing: 0) { page; Divider(); fields.frame(width: 300) }
                } else {
                    VStack(spacing: 0) { page; Divider(); fields.frame(height: space.size.height * 0.45) }
                }
            }
            .navigationTitle("Chronicle Sheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep", action: keep).disabled(!canKeep)
                        .accessibilityIdentifier("sheet-keep")
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task(id: turns) { await read() }
        #if os(macOS)
        .frame(minWidth: 820, idealWidth: 980, minHeight: 640, idealHeight: 780)
        #endif
    }

    // MARK: - The page

    private var page: some View {
        SheetPageView(pdf: pdf, version: turns, marks: Array((located?.places ?? [:]).values))
            .overlay(alignment: .bottom) { turnButtons.padding(12) }
            .accessibilityLabel("The chronicle sheet")
    }

    private var turnButtons: some View {
        HStack(spacing: 12) {
            Button { turn(by: -1) } label: { Label("Rotate Left", systemImage: "rotate.left") }
            Button { turn(by: 1) } label: { Label("Rotate Right", systemImage: "rotate.right") }
        }
        .labelStyle(.iconOnly).buttonStyle(.bordered).controlSize(.large)
        .padding(6).background(.regularMaterial, in: Capsule())
    }

    /// A sideways page reads as nothing, so a turned sheet is read again. A page turned all the way round is the
    /// file as it came.
    private func turn(by quarterTurns: Int) {
        let total = ((turns + quarterTurns) % 4 + 4) % 4
        let turned = total == 0 ? candidate.pdf : SheetPage.turned(candidate.pdf, quarterTurns: total)
        guard let turned else { return }
        pdf = turned
        turns = total
    }

    // MARK: - What was read

    private var fields: some View {
        ScrollView {
            SheetFields(draft: $draft, state: fieldsState).padding(16)
        }
    }

    private var fieldsState: SheetFields.State {
        SheetFields.State(
            adventure: sheet.isNew ? "New Chronicle Sheet" : session.adventure.title, currency: currency,
            read: located?.reading, showsKeptValues: candidate.isAttached && sheet.reading != nil,
            mismatches: located == nil ? [] : mismatches, unreadable: draft.unreadableFields(in: currency),
            isReported: session.isReported)
    }

    /// How the values as they stand in the fields disagree with the session and the ledger. Gold that an earlier
    /// reading of this sheet put in the ledger doesn't count: keeping replaces it (R5.11).
    private var mismatches: [SheetMismatch] {
        let entered = record.settings.wealth.earned[session.keyWithinCharacter]
        let isSheetsOwn = candidate.isAttached && entered != nil && entered == sheet.reading?.funds
        return SheetChecker(record: record, roster: store.roster).mismatches(of: corrected, with: session)
            .filter { $0.kind != .funds || !isSheetsOwn }
    }

    private var corrected: SheetReading {
        draft.reading(correcting: located?.reading ?? SheetReading(), currency: currency)
    }

    /// The first reading fills the fields, with the values kept earlier for a sheet that is read again. A later
    /// one, after a turn, leaves what the user typed.
    private func read() async {
        let fresh = await store.read(pdf)
        guard !Task.isCancelled else { return }
        if let earlier = located {
            draft.refill(
                from: SheetDraft(reading: fresh.reading, currency: currency),
                replacing: SheetDraft(reading: earlier.reading, currency: currency))
        } else {
            let kept = candidate.isAttached ? sheet.reading : nil
            draft = SheetDraft(reading: kept ?? fresh.reading, currency: currency)
            // The day the user chose earlier; a new sheet starts on today, as few are added later than that.
            if !session.isReported { draft.day = kept?.playedOn.flatMap { SheetDay.localDate(of: $0) } ?? Date() }
        }
        located = fresh
    }

    // MARK: - Keep

    /// A sheet added ahead of its report needs its scenario number, which is what its session is found by.
    private var canKeep: Bool {
        located != nil && draft.unreadableFields(in: currency).isEmpty && (session.isReported || draft.hasCode)
    }

    /// Saves the PDF as shown and the values as they stand. A sheet that couldn't be saved keeps no reading.
    private func keep() {
        let isNewFile = !candidate.isAttached || turns != 0
        if isNewFile, !store.attachChronicle(pdf, to: session, characterNumber: record.id) { return dismiss() }
        store.keep(corrected, for: session, characterNumber: record.id)
        dismiss()
    }
}

extension View {
    /// Shows the confirmation for a PDF that is to be a session's chronicle sheet. On the iPhone and iPad it takes
    /// the whole screen, so the page is large enough to check handwriting against; on the Mac it is a sheet.
    func sheetConfirmation(_ candidate: Binding<SheetCandidate?>, for sheet: SessionSheet) -> some View {
        #if os(iOS)
        fullScreenCover(item: candidate) { SheetConfirmation(candidate: $0, sheet: sheet) }
        #else
        self.sheet(item: candidate) { SheetConfirmation(candidate: $0, sheet: sheet) }
        #endif
    }
}
