import Foundation
import Testing
@testable import CharacterKeeperKit

@Suite struct URLSessionHTTPClientTests {
    @Test func configurationKeepsCookiesInMemoryAndIdentifiesTheApp() {
        let configuration = URLSessionHTTPClient.makeConfiguration()
        let agent = configuration.httpAdditionalHeaders?["User-Agent"] as? String
        #expect(agent?.contains(" CharacterKeeper/") == true)
        #expect(agent?.contains("(+https://github.com/scooper4711/character-keeper)") == true)
        #expect(configuration.httpCookieAcceptPolicy == .always)
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func userAgentNamesTheAppItsVersionAndItsProjectAfterSafari() {
        let agent = URLSessionHTTPClient.userAgent(version: "1.4.2")
        #expect(agent.hasPrefix("Mozilla/5.0 "))
        #expect(agent.contains(" Safari/"))
        #expect(agent.hasSuffix(" CharacterKeeper/1.4.2 (+https://github.com/scooper4711/character-keeper)"))
    }
}
