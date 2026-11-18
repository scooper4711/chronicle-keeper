import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let finalURL: URL?

    public init(data: Data, statusCode: Int = 200, finalURL: URL? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.finalURL = finalURL
    }

    // Lossy fallback on purpose: invalid bytes get replaced rather than losing the whole page.
    // swiftlint:disable:next optional_data_string_conversion
    public var text: String { String(bytes: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self) }

    /// Returns the response, or throws when the status is not a success.
    public func validated(operation: String) throws -> HTTPResponse {
        guard (200..<300).contains(statusCode) else {
            throw OrganizedPlayError.http(operation: operation, status: statusCode)
        }
        return self
    }
}

/// The network access the app needs. Tests replace it with a stub.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

extension URLRequest {
    /// A form post the way the site's Ajax buttons send it.
    static func postAjaxForm(_ url: URL, fields: [(name: String, value: String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.httpBody = Data(fields.map { "\(formEncode($0.name))=\(formEncode($0.value))" }
            .joined(separator: "&").utf8)
        return request
    }

    static func ajaxGet(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return request
    }

    private static func formEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return (text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text)
            .replacingOccurrences(of: "%20", with: "+")
    }
}
