import Foundation

/// The paizo.com addresses the app uses.
public struct OrganizedPlayEndpoints: Sendable {
    public let base: URL

    public init(base: URL = URL(string: "https://paizo.com")!) { // swiftlint:disable:this force_unwrapping
        self.base = base
    }

    public var signInPage: URL {
        url("/cgi-bin/WebObjects/Store.woa/wa/DirectAction/signIn?path=organizedplay/myAccount")
    }

    public var summaryPage: URL {
        url("/cgi-bin/WebObjects/Store.woa/wa/browse?path=organizedPlay/myAccount/player")
    }

    public var sessionsPage: URL {
        url("/cgi-bin/WebObjects/Store.woa/wa/browse?path=organizedPlay/myAccount/allsessions")
    }

    /// An Ajax update: the component URL with the update container and a cache-busting timestamp, as the
    /// site's own script sends it.
    public func ajaxUpdate(path: String, containerID: String, timestamp: Date = Date()) -> URL {
        let millis = Int64(timestamp.timeIntervalSince1970 * 1000)
        let separator = path.contains("?") ? "&" : "?"
        return url("\(path)\(separator)_u=\(containerID)&\(millis)")
    }

    func url(_ pathAndQuery: String) -> URL {
        URL(string: pathAndQuery, relativeTo: base)?.absoluteURL ?? base
    }
}
