import Foundation
import Testing
@testable import ChronicleKeeperKit

@Suite struct URLSessionHTTPClientTests {
    @Test func configurationKeepsCookiesInMemoryAndIdentifiesTheApp() {
        let configuration = URLSessionHTTPClient.makeConfiguration()
        let agent = configuration.httpAdditionalHeaders?["User-Agent"] as? String
        #expect(agent?.contains(" ChronicleKeeper/") == true)
        #expect(agent?.contains("(+https://github.com/scooper4711/chronicle-keeper)") == true)
        #expect(configuration.httpCookieAcceptPolicy == .always)
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func userAgentNamesTheAppItsVersionAndItsProjectAfterSafari() {
        let agent = URLSessionHTTPClient.userAgent(version: "1.4.2")
        #expect(agent.hasPrefix("Mozilla/5.0 "))
        #expect(agent.contains(" Safari/"))
        #expect(agent.hasSuffix(" ChronicleKeeper/1.4.2 (+https://github.com/scooper4711/chronicle-keeper)"))
    }
}
