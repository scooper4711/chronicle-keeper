import Foundation
import SwiftSoup

/// Reads a character's portrait from their public Demiplane sheet, whose page names it in its `og:image` tag.
/// No sign-in is involved, and only Demiplane's sheet pages and portrait storage are ever contacted.
public struct DemiplanePortraitSource: Sendable {
    static let operation = "Reading the Demiplane portrait"
    static let sheetHost = "app.demiplane.com"
    static let imageHost = "demiplane-prod-app-avatar.s3.us-west-2.amazonaws.com"

    private let http: any HTTPClient

    public init(http: any HTTPClient) {
        self.http = http
    }

    /// The sheet's address without any query or fragment, when the link is a Demiplane character sheet.
    public static func sheetURL(from link: URL?) -> URL? {
        guard let link, link.scheme?.lowercased() == "https", link.host()?.lowercased() == sheetHost else {
            return nil
        }
        let parts = link.pathComponents
        guard parts.count == 5, parts[1] == "nexus", parts[3] == "character-sheet",
              UUID(uuidString: parts[4]) != nil else { return nil }
        var address = URLComponents()
        address.scheme = "https"
        address.host = sheetHost
        address.path = link.path()
        return address.url
    }

    /// The portrait's image data for a sheet address from `sheetURL(from:)`.
    public func imageData(forSheet sheet: URL) async throws -> Data {
        let page = try await http.send(URLRequest(url: sheet)).validated(operation: Self.operation)
        try requireHost(of: page.finalURL ?? sheet, is: Self.sheetHost)
        guard let image = try Self.portraitURL(inPage: page.text) else {
            throw PortraitError(
                operation: Self.operation, failure: "the sheet shows no portrait, or it isn't shared publicly")
        }
        let response = try await http.send(URLRequest(url: image)).validated(operation: Self.operation)
        try requireHost(of: response.finalURL ?? image, is: Self.imageHost)
        return response.data
    }

    /// The page's portrait, when it is kept in Demiplane's portrait storage. Their generic artwork isn't.
    static func portraitURL(inPage html: String) throws -> URL? {
        let tag = try SwiftSoup.parse(html).select("meta[property=og:image]").first()
        guard let content = try tag?.attr("content"), let url = URL(string: content),
              url.scheme == "https", url.host() == imageHost else { return nil }
        return url
    }

    /// A redirect mustn't take the request anywhere else.
    private func requireHost(of url: URL, is host: String) throws {
        guard url.scheme == "https", url.host() == host else {
            throw PortraitError(operation: Self.operation, failure: "Demiplane sent the request somewhere else")
        }
    }
}
