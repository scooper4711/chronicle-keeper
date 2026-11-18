import Foundation
import SwiftSoup

/// Tells a refused sign-in from a sign-in that paizo.com no longer handles the way the app expects, so that a
/// change on the site never looks like a wrong password.
public enum SignInReply {
    /// Throws unless the account page shows the user signed in.
    /// - Parameters:
    ///   - reply: what paizo.com answered to the submitted form.
    ///   - accountPage: the account page read after submitting.
    public static func check(reply: String, accountPage: String) throws {
        guard SignInFormParser.isSignInPage(accountPage) else { return }
        guard SignInFormParser.isSignInPage(reply) else {
            throw OrganizedPlayError.signInChanged(
                reason: "paizo.com took the sign-in but still asks for a password, so its sign-in has changed")
        }
        throw OrganizedPlayError.signInRejected(paizoSays: errorText(in: reply))
    }

    /// Throws when the sign-in page asks for something the app can't give, such as a captcha.
    public static func checkSupported(signInPage html: String) throws {
        let lowered = html.lowercased()
        if captchaMarkers.contains(where: lowered.contains) {
            throw OrganizedPlayError.signInChanged(
                reason: "paizo.com now asks for a captcha, which the app can't answer")
        }
    }

    /// The first error message the reply shows, or empty when it shows none the app can find.
    static func errorText(in html: String) -> String {
        guard let document = try? SwiftSoup.parse(html),
              let elements = try? document.select(errorSelector).array() else { return "" }
        // The innermost match: Paizo nests its message inside a box of the same class with an "Important" title.
        let innermost = elements.filter { (try? $0.select(errorSelector).size()) == 1 }
        let texts = innermost.compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(texts.first { !$0.isEmpty }?.prefix(200) ?? "")
    }

    private static let errorSelector = [
        "[class*=error]", "[class*=Error]", "[class*=alert]", "[class*=warning]", "[id*=error]", "[id*=Error]",
        "font[color=red]", "font[color=#ff0000]", "[style*=color: red]", "[style*=color:red]"
    ].joined(separator: ", ")

    private static let captchaMarkers = ["g-recaptcha", "h-captcha", "cf-turnstile", "recaptcha/api", "hcaptcha.com"]
}
