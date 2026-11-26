import ChronicleKeeperKit
import SwiftUI

/// Under a session's chronicle sheet: what was read from it, with the way to correct it, and each warning it
/// raises with what the user can do about it (R1.12). Nothing for a sheet that hasn't been read.
struct SheetReadingSummary: View {
    let sheet: SessionSheet
    let edit: () -> Void

    var body: some View {
        if let reading = sheet.reading {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("From the sheet: \(reading.summary(in: sheet.currency))")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sheet-reading-summary")
                    Spacer(minLength: 8)
                    Button("Edit", action: edit).buttonStyle(.borderless)
                        .accessibilityIdentifier("sheet-reading-edit")
                        .accessibilityHint("Shows the sheet with what was read from it")
                }
                ForEach(sheet.warnings) { warning in
                    SheetWarningRow(warning: warning, sheet: sheet)
                }
            }
        }
    }
}

/// One warning about a sheet, in words, with its buttons: nothing is blocked, and the user clears a warning once
/// satisfied.
struct SheetWarningRow: View {
    let warning: SheetMismatch
    let sheet: SessionSheet

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SheetWarningText(text: warning.message)
            HStack(spacing: 8) {
                if warning.kind == .funds {
                    Button("Use the Sheet's Amount") { sheet.useSheetAmount() }
                }
                Button("Clear Warning") { sheet.clear(warning) }
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Under an adventure's gold in the ledger (R5.11): a mark when the amount is the chronicle sheet's, or the
/// warning when the sheet gives another amount than was typed.
struct SheetFundsNote: View {
    let sheet: SessionSheet

    var body: some View {
        if let funds = sheet.reading?.funds {
            if sheet.record.settings.wealth.earned[sheet.session.keyWithinCharacter] == funds {
                Label("From the Chronicle Sheet", systemImage: "doc.text")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let warning = sheet.warnings.first(where: { $0.kind == .funds }) {
                SheetWarningRow(warning: warning, sheet: sheet)
            }
        }
    }
}
