import Foundation

/// What went wrong talking to paizo.com, with the operation it happened in.
public enum OrganizedPlayError: Error, Equatable, LocalizedError {
    case http(operation: String, status: Int)
    /// paizo.com showed the sign-in form again. `paizoSays` is its own error text, or empty when it gave none.
    case signInRejected(paizoSays: String)
    /// Signing in no longer works the way the app does it, such as a new captcha or a different flow.
    case signInChanged(reason: String)
    case noCredentials
    case incompletePaging(read: Int, total: Int)
    case unexpectedPage(operation: String)

    public var errorDescription: String? {
        switch self {
        case .http(let operation, let status):
            "\(operation) failed: paizo.com answered with HTTP \(status)."
        case .signInRejected(let paizoSays) where !paizoSays.isEmpty:
            "paizo.com didn't accept the sign-in: “\(paizoSays)”"
        case .signInRejected:
            "paizo.com didn't accept the email address and password."
        case .signInChanged(let reason):
            "Signing in to paizo.com failed: \(reason)."
        case .noCredentials:
            "Sign in to paizo.com first."
        case .incompletePaging(let read, let total):
            "Reading the Sessions tab stopped after \(read) of \(total) sessions."
        case .unexpectedPage(let operation):
            "\(operation) failed: paizo.com showed a page the app doesn't recognize."
        }
    }
}
