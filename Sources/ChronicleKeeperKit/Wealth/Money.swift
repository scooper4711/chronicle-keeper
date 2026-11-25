import Foundation

/// What a campaign pays in: Pathfinder in gold, silver and copper; Starfinder in credits.
public enum Currency: Sendable {
    case gold
    case credits
}

/// Amounts of money. Every amount in the app is an `Int` of copper pieces: 1 gp is 100, 1 sp is 10, and a credit
/// is worth 1 sp ("1 credit = 1 sp", Starfinder Society Guide), so it is 10.
public enum Money {
    public static let copperPerGold = 100
    public static let copperPerSilver = 10
    public static let copperPerCredit = 10

    /// "11 gp, 2 sp" or "112 credits"; parts that are zero are left out, and nothing at all is "0 gp".
    public static func format(_ copper: Int, in currency: Currency, locale: Locale = .autoupdatingCurrent) -> String {
        let sign = copper < 0 ? "−" : ""
        let amount = abs(copper)
        switch currency {
        case .gold: return sign + goldParts(of: amount, locale: locale)
        case .credits: return sign + credits(of: amount, locale: locale)
        }
    }

    /// Reads what the user typed: "11.2" (gold pieces) or "11 gp 2 sp" in gold, a number of credits otherwise.
    /// Thousands separators are allowed. Nil for anything else, including a negative amount.
    public static func parse(_ text: String, in currency: Currency) -> Int? {
        let cleaned = text.lowercased().replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "credits", with: "").replacingOccurrences(of: "credit", with: "")
            .replacingOccurrences(of: "cr", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        switch currency {
        case .gold: return parseGold(cleaned)
        case .credits: return copper(fromDecimal: cleaned, unit: copperPerCredit)
        }
    }

    private static func goldParts(of amount: Int, locale: Locale) -> String {
        let parts = [
            (amount / copperPerGold, "gp"),
            (amount % copperPerGold / copperPerSilver, "sp"),
            (amount % copperPerSilver, "cp")
        ]
        let shown = parts.filter { $0.0 > 0 }.map { "\($0.0.formatted(.number.locale(locale))) \($0.1)" }
        return shown.isEmpty ? "0 gp" : shown.joined(separator: ", ")
    }

    private static func credits(of amount: Int, locale: Locale) -> String {
        let value = Decimal(amount) / Decimal(copperPerCredit)
        return "\(value.formatted(.number.locale(locale))) credits"
    }

    private static func parseGold(_ text: String) -> Int? {
        guard text.contains(where: \.isLetter) else { return copper(fromDecimal: text, unit: copperPerGold) }
        let units = ["gp": copperPerGold, "sp": copperPerSilver, "cp": 1]
        var total = 0
        var rest = Substring(text)
        while let match = rest.firstMatch(of: /^\s*(\d+(?:\.\d+)?)\s*(gp|sp|cp)\s*/) {
            guard let unit = units[String(match.2)],
                  let value = copper(fromDecimal: String(match.1), unit: unit) else { return nil }
            total += value
            rest = rest[match.range.upperBound...]
        }
        return rest.isEmpty ? total : nil
    }

    /// A non-negative decimal number of `unit`s in copper; nil when it isn't one, or has a fraction of a copper.
    private static func copper(fromDecimal text: String, unit: Int) -> Int? {
        guard text.wholeMatch(of: /\d*(\.\d*)?/) != nil, text != ".",
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let copper = value * Decimal(unit)
        var rounded = Decimal()
        var source = copper
        NSDecimalRound(&rounded, &source, 0, .plain)
        guard rounded == copper else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
