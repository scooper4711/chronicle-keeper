import Foundation
import SwiftSoup

/// The sign-in form: where it posts, its hidden fields, and the Ajax button that submits it.
public struct SignInForm: Equatable, Sendable {
    public let action: String
    public let hiddenFields: [String: String]
    public let emailField: String
    public let passwordField: String
    public let buttonName: String
    public let containerID: String

    /// The fields the site's script posts: the form's inputs and the button that was pressed.
    public func fields(for credentials: Credentials) -> [(name: String, value: String)] {
        hiddenFields.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
            + [(emailField, credentials.email), (passwordField, credentials.password),
               ("AJAX_SUBMIT_BUTTON_NAME", buttonName)]
    }

    /// The Ajax form of the action: `/wo/` becomes `/ajax/`.
    public var ajaxActionPath: String {
        action.replacingOccurrences(of: "/wo/", with: "/ajax/")
    }
}

public enum SignInFormParser {
    /// True when the page asks for a password, which means the app isn't signed in.
    public static func isSignInPage(_ html: String) -> Bool {
        html.firstMatch(of: passwordInputPattern) != nil
    }

    // Any quoting and spacing, so a small markup change still counts as the sign-in page.
    nonisolated(unsafe) private static let passwordInputPattern = /(?i)type\s*=\s*["']?password\b/

    public static func form(in html: String) throws -> SignInForm {
        let operation = "Reading the sign-in page"
        let document = try parseDocument(html, operation: operation)
        let forms = try document.select("form").array()
        guard let form = try forms.first(where: { try !$0.select("input[type=password]").isEmpty() }),
              let password = try form.select("input[type=password]").first(),
              let email = try form.select("input[type=text], input[type=email]").first(),
              let button = try form.select("button").array().first(where: { try $0.text() == "Sign In" })
        else { throw ParsingError(operation: operation, reason: "there is no sign-in form") }
        let onclick = try button.attr("onclick")
        guard let container = onclick.firstMatch(of: /ASB\.update\('([^']+)'/) else {
            throw ParsingError(operation: operation, reason: "the Sign In button has no Ajax target")
        }
        var hidden: [String: String] = [:]
        for input in try form.select("input[type=hidden]").array() {
            hidden[try input.attr("name")] = try input.attr("value")
        }
        return SignInForm(
            action: try form.attr("action"), hiddenFields: hidden, emailField: try email.attr("name"),
            passwordField: try password.attr("name"), buttonName: try button.attr("name"),
            containerID: String(container.1)
        )
    }
}
