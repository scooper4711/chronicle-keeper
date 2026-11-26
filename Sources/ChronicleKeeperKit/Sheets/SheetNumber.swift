import Foundation

/// Reads the numbers written in a chronicle sheet's boxes. Each takes a clean number and nothing else: anything it
/// would have to guess at is nil (R1.10).
enum SheetNumber {
    /// XP as written: "4", "+ 4", "4.0", "0,5" or "2 XP".
    static func xp(_ text: String) -> Double? {
        let cleaned = withoutSign(text.lowercased()).replacingOccurrences(of: "xp", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.wholeMatch(of: /\d{1,2}([.,]\d)?0?/) != nil else { return nil }
        return Double(cleaned.replacingOccurrences(of: ",", with: "."))
    }

    /// An amount of gold or credits in copper: "220", "+ 220", "11.2 gp", "1,234" or "176.00". Sheets are filled in
    /// by GMs everywhere, so the decimal mark may be a point or a comma: a mark before exactly three digits
    /// separates thousands, one before one or two digits is the decimal mark. "14 gp 4 sp" isn't one clean number.
    static func funds(_ text: String, in currency: Currency) -> Int? {
        let cleaned = withoutUnit(withoutSign(text.lowercased()), of: currency)
        let unit = currency == .credits ? Money.copperPerCredit : Money.copperPerGold
        if cleaned.wholeMatch(of: /\d{1,3}([.,\u{20}]\d{3})+/) != nil {
            return Int(cleaned.filter(\.isNumber)).map { $0 * unit }
        }
        guard let match = cleaned.wholeMatch(of: /(\d+)(?:[.,](\d{1,2}))?/), let whole = Int(match.1) else {
            return nil
        }
        let fraction = match.2.map(String.init) ?? ""
        let hundredths = (Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0)
        let copperTimesHundred = (whole * 100 + hundredths) * unit
        return copperTimesHundred.isMultiple(of: 100) ? copperTimesHundred / 100 : nil
    }

    /// The runs of digits in a line, left to right: "2409341• 2702" is 2409341 and 2702.
    static func digitRuns(in text: String) -> [String] {
        text.split { !$0.isASCII || !$0.isNumber }.map(String.init)
    }

    /// An event code as paizo.com gives it, without the separators a GM or a program adds: "8,538,127".
    static func eventCode(_ text: String) -> String? {
        let cleaned = text.filter { !" ,.".contains($0) }
        return cleaned.count >= 3 && cleaned.allSatisfy { $0.isASCII && $0.isNumber } ? cleaned : nil
    }

    /// The sheet prints a "+" before the boxes a GM adds to, which recognition may read with the number.
    private static func withoutSign(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("+") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) : trimmed
    }

    private static func withoutUnit(_ text: String, of currency: Currency) -> String {
        let units = currency == .credits ? ["credits", "credit", "cr"] : ["gp"]
        let unit = units.first { text.hasSuffix($0) } ?? ""
        return String(text.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
    }
}
