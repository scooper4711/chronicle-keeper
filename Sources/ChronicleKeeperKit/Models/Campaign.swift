import Foundation

/// An Organized Play campaign, as the My Organized Play pages name it.
public enum Campaign: Hashable, Codable, Sendable {
    case pathfinder1
    case pathfinder2
    case starfinder1
    case starfinder2
    case other(String)

    /// Reads the code the site uses in the Summary table and in the Points column ("PFS(2ed)", "SFS2", …).
    public init(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.uppercased() {
        case "PFS", "PFS(1ED)", "PFS1": self = .pathfinder1
        case "PFS(2ED)", "PFS2": self = .pathfinder2
        case "SFS", "SFS(1ED)", "SFS1": self = .starfinder1
        case "SFS2", "SFS(2ED)": self = .starfinder2
        default: self = .other(trimmed)
        }
    }

    public var displayName: String {
        switch self {
        case .pathfinder1: "Pathfinder Society (1st Edition)"
        case .pathfinder2: "Pathfinder Society (2nd Edition)"
        case .starfinder1: "Starfinder Society (1st Edition)"
        case .starfinder2: "Starfinder Society (2nd Edition)"
        case .other(let code): code
        }
    }

    public var shortName: String {
        switch self {
        case .pathfinder1: "PFS1"
        case .pathfinder2: "PFS2"
        case .starfinder1: "SFS1"
        case .starfinder2: "SFS2"
        case .other(let code): code
        }
    }

    /// The order campaigns appear in the sidebar.
    public var sortOrder: Int {
        switch self {
        case .pathfinder2: 0
        case .starfinder2: 1
        case .pathfinder1: 2
        case .starfinder1: 3
        case .other: 4
        }
    }
}
