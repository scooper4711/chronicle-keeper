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

    /// Always in gold pieces or credits, as the chronicles give them: "11.2 gp", "0.05 gp" or "112 credits".
    public static func format(_ copper: Int, in currency: Currency, locale: Locale = .autoupdatingCurrent) -> String {
        let sign = copper < 0 ? "−" : ""
        let amount = abs(copper)
        switch currency {
        case .gold: return sign + decimal(amount, unit: copperPerGold, locale: locale) + " gp"
        case .credits: return sign + decimal(amount, unit: copperPerCredit, locale: locale) + " credits"
        }
    }

    /// Reads what the user typed: "11.2" (gold pieces) or "11 gp 2 sp" in gold, a number of credits otherwise.
    /// Numbers follow the locale: its decimal mark ("11,5" in Norwegian is 11.5) and its thousands separator,
    /// which counts only before exactly three digits. A comma between digits that is neither is refused rather
    /// than guessed at. Nil for anything else, including a negative amount.
    public static func parse(_ text: String, in currency: Currency, locale: Locale = .autoupdatingCurrent) -> Int? {
        let numbers = plainNumbers(in: text.lowercased(), locale: locale)
        guard numbers.firstMatch(of: /\d,\d/) == nil else { return nil }
        let cleaned = numbers.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "credits", with: "").replacingOccurrences(of: "credit", with: "")
            .replacingOccurrences(of: "cr", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        switch currency {
        case .gold: return parseGold(cleaned)
        case .credits: return copper(fromDecimal: cleaned, unit: copperPerCredit)
        }
    }

    /// The text with thousands separators dropped and the locale's decimal mark made a point, both only between
    /// digits, so the comma between "11 gp, 2 sp" stays a separator.
    private static func plainNumbers(in text: String, locale: Locale) -> String {
        let decimal = locale.decimalSeparator ?? "."
        let grouping = Set([locale.groupingSeparator ?? ",", ",", " ", "\u{00A0}", "\u{202F}"]).subtracting([decimal])
        var result = text
        for separator in grouping {
            result = replace(separator, beforeDigits: "\\d{3}(?!\\d)", with: "", in: result)
        }
        return replace(decimal, beforeDigits: "\\d", with: ".", in: result)
    }

    /// Replaces `separator` where a digit comes before it and `digits` (a pattern) after it.
    private static func replace(_ separator: String, beforeDigits digits: String, with replacement: String,
                                in text: String) -> String {
        let pattern = "(?<=\\d)" + NSRegularExpression.escapedPattern(for: separator) + "(?=" + digits + ")"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

    private static func decimal(_ amount: Int, unit: Int, locale: Locale) -> String {
        (Decimal(amount) / Decimal(unit)).formatted(.number.locale(locale))
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
