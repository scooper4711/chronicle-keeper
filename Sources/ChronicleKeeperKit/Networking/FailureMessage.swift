import Foundation

/// What to tell the user when talking to paizo.com fails: one message for each kind of failure, so a change on
/// Paizo's website is never shown as a wrong password, an empty list or a spinner that never stops.
public enum FailureMessage {
    /// The message for `error`, as the sign-in screen and the status bar show it.
    public static func text(for error: Error) -> String {
        if isSiteChange(error) {
            return siteChanged(detail: detail(of: error))
        }
        if let urlError = error as? URLError {
            return text(for: urlError)
        }
        switch error {
        case OrganizedPlayError.http(let operation, let status) where status >= 500:
            return "\(operation) failed: paizo.com isn't working right now (HTTP \(status)). Try again later."
        case OrganizedPlayError.signInRejected(let paizoSays) where paizoSays.isEmpty:
            return "paizo.com didn't accept the email address and password. If they are right, Paizo's sign-in may "
                + "have changed. " + remedy
        default:
            return error.localizedDescription
        }
    }

    /// True when Paizo's pages or answers no longer look the way the app reads them.
    public static func isSiteChange(_ error: Error) -> Bool {
        switch error {
        case is ParsingError, OrganizedPlayError.signInChanged, OrganizedPlayError.unexpectedPage,
             OrganizedPlayError.incompletePaging:
            true
        case OrganizedPlayError.http(_, let status):
            status == 404 || status == 410
        default:
            false
        }
    }

    /// Says what happened and where to find a version that follows the change.
    public static func siteChanged(detail: String) -> String {
        "Paizo's website has changed, and this version of Chronicle Keeper can't read it (\(detail)). " + remedy
    }

    #if APP_STORE || os(iOS)
    public static let remedy = "Check the App Store for an update of Chronicle Keeper."
    #else
    public static let remedy =
        "Look for a newer version at github.com/scooper4711/chronicle-keeper/releases."
    #endif

    private static func detail(of error: Error) -> String {
        let text = (error as? ParsingError)?.description ?? error.localizedDescription
        return text.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private static func text(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            "You are not connected to the internet. Connect and try again."
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            "paizo.com didn't answer. Check your connection, or try again later."
        default:
            error.localizedDescription
        }
    }
}
