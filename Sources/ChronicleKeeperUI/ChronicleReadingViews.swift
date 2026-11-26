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
            adventure: session.adventure.title, currency: currency, read: located?.reading,
            showsKeptValues: candidate.isAttached && sheet.reading != nil,
            mismatches: located == nil ? [] : mismatches, unreadable: draft.unreadableFields(in: currency))
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
        }
        located = fresh
    }

    // MARK: - Keep

    private var canKeep: Bool {
        located != nil && draft.unreadableFields(in: currency).isEmpty
    }

    /// Saves the PDF as shown and the values as they stand. A sheet that couldn't be saved keeps no reading.
    private func keep() {
        let isNewFile = !candidate.isAttached || turns != 0
        if isNewFile, !store.attachChronicle(pdf, to: session, characterNumber: record.id) { return dismiss() }
        store.keep(corrected, for: session, characterNumber: record.id)
        dismiss()
    }
}

/// The confirmation's fields: where the values came from, then the character number, the XP and the gold, each
/// with what is wrong with it underneath.
struct SheetFields: View {
    /// What the fields show besides their text.
    struct State {
        let adventure: String
        let currency: Currency
        /// What was read from the sheet; nil while it is being read.
        let read: SheetReading?
        /// Whether the fields began with what the user kept for this sheet earlier, not with what was just read.
        let showsKeptValues: Bool
        let mismatches: [SheetMismatch]
        let unreadable: Set<SheetField>
    }

    @Binding var draft: SheetDraft
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.adventure).font(.headline).fixedSize(horizontal: false, vertical: true)
                if let warning = warning(.adventure) { SheetWarningText(text: warning) }
            }
            source
            field(.characterNumber, title: "Character Number", prompt: "123456-2001")
            field(.xp, title: "XP", prompt: "4")
            field(.funds, title: money, prompt: state.currency == .credits ? "220" : "11.2")
            Text("\(money) includes Earn Income only where the GM wrote it in. Empty a value you'd rather the app "
                + "worked out as it does without a sheet.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(state.read == nil)
    }

    private var money: String { state.currency == .credits ? "Credits" : "Gold" }

    /// Text from the PDF can't be misread; recognized handwriting can.
    @ViewBuilder private var source: some View {
        if let read = state.read {
            Text(state.showsKeptValues ? Self.keptNote : Self.sourceNote(for: read))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            ProgressView { Text("Reading the sheet…").foregroundStyle(.secondary) }
        }
    }

    private static let keptNote = "These are the values you kept for this sheet. Correct them here, or empty one "
        + "to have the app work it out as it does without a sheet."

    private static func sourceNote(for read: SheetReading) -> String {
        if read.playerNumber == nil && read.characterPart == nil && read.xp == nil && read.funds == nil {
            return "Nothing could be read from this sheet for certain. Type its values, or leave them empty."
        }
        switch read.source {
        case .pdfText: return "Read from the PDF's own text. Anything left empty couldn't be read for certain."
        case .recognized:
            return "Read from the picture of the sheet. Handwriting is easy to misread, so check each value "
                + "against the sheet. Anything left empty couldn't be read for certain."
        }
    }

    private func field(_ field: SheetField, title: String, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            TextField(title, text: $draft[field], prompt: Text(prompt))
                .textFieldStyle(.roundedBorder).monospacedDigit().labelsHidden()
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .accessibilityLabel(title)
                .accessibilityIdentifier("sheet-field-\(field.rawValue)")
            if state.unreadable.contains(field) {
                Text("This isn't a number the app can read. Correct it, or empty the field.")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if let warning = warning(Self.kind(of: field)) {
                SheetWarningText(text: warning)
            }
        }
    }

    private func warning(_ kind: SheetMismatch.Kind) -> String? {
        state.mismatches.first { $0.kind == kind }?.message
    }

    private static func kind(of field: SheetField) -> SheetMismatch.Kind {
        switch field {
        case .characterNumber: .character
        case .xp: .xp
        case .funds: .funds
        }
    }
}

/// A disagreement between the sheet and the record, in words, with the warning's sign.
struct SheetWarningText: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
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
