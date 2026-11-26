import ChronicleKeeperKit
import SwiftUI

/// The confirmation's fields: where the values came from, then the character number, the XP and the gold, each
/// with what is wrong with it underneath. A sheet added ahead of its report starts with the scenario number and
/// the day played (R1.14).
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
        /// Whether paizo.com lists the session; when it doesn't, the sheet says what was played and when.
        let isReported: Bool
    }

    @Binding var draft: SheetDraft
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.adventure).font(.headline).fixedSize(horizontal: false, vertical: true)
                if state.isReported, let warning = warning(.adventure) { SheetWarningText(text: warning) }
            }
            source
            if !state.isReported { unreportedFields }
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

    /// What makes the session until paizo.com lists it: the scenario number and the day played.
    @ViewBuilder private var unreportedFields: some View {
        Text("paizo.com doesn't list this session yet. The sheet counts right away, and goes to its session when "
            + "the GM reports it.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        field(.code, title: "Scenario Number", prompt: "6-04")
        VStack(alignment: .leading, spacing: 4) {
            Text("Day Played").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            DatePicker("Day Played", selection: day, in: ...Date(), displayedComponents: .date)
                .labelsHidden().accessibilityIdentifier("sheet-field-day")
        }
    }

    private var day: Binding<Date> {
        Binding { draft.day ?? Date() } set: { draft.day = $0 }
    }

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
                // A scenario number can be "Quest 14".
                .keyboardType(field == .code ? .default : .numbersAndPunctuation)
                .autocorrectionDisabled()
                #endif
                .accessibilityLabel(title)
                .accessibilityIdentifier("sheet-field-\(field.rawValue)")
            if state.unreadable.contains(field) {
                Text(field == .code ? "This isn't a scenario number: write it as 6-04, Quest 14 or Bounty 19."
                    : "This isn't a number the app can read. Correct it, or empty the field.")
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
        case .code: .adventure
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
