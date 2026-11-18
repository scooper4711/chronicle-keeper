import Foundation

/// What went wrong talking to paizo.com, with the operation it happened in.
public enum OrganizedPlayError: Error, Equatable, LocalizedError {
    case http(operation: String, status: Int)
    case signInRejected
    case noCredentials
    case incompletePaging(read: Int, total: Int)
    case unexpectedPage(operation: String)

    public var errorDescription: String? {
        switch self {
        case .http(let operation, let status):
            "\(operation) failed: paizo.com answered with HTTP \(status)."
        case .signInRejected:
            "Signing in to paizo.com failed: check the email address and password."
        case .noCredentials:
            "Sign in to paizo.com first."
        case .incompletePaging(let read, let total):
            "Reading the Sessions tab stopped after \(read) of \(total) sessions."
        case .unexpectedPage(let operation):
            "\(operation) failed: paizo.com showed a page the app doesn't recognize."
        }
    }
}
