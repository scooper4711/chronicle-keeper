import Foundation

/// `HTTPClient` backed by a `URLSession` that keeps paizo.com's session cookies in memory.
public final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = URLSessionHTTPClient.makeConfiguration()) {
        session = URLSession(configuration: configuration)
    }

    /// An in-memory configuration: cookies and caches are not written to disk.
    public static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent(version: appVersion)]
        return configuration
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(data: data, statusCode: status, finalURL: response.url)
    }

    /// Safari's user agent, so paizo.com treats the app like a browser, then the app's name, version and project
    /// page, so Paizo can tell its requests apart.
    static func userAgent(version: String) -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 "
            + "Safari/605.1.15 CharacterKeeper/\(version) (+https://github.com/scooper4711/character-keeper)"
    }

    /// The running app's version; "0" where there is no app bundle, as in the unit tests.
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
