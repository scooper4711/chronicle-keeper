import Foundation

/// A page didn't look the way the parser expects.
public struct ParsingError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    public let reason: String

    public init(operation: String, reason: String) {
        self.operation = operation
        self.reason = reason
    }

    public var description: String { "\(operation) failed: \(reason)" }
}
