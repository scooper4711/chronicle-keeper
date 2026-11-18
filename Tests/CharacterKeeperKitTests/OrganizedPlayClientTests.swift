import Foundation
import Testing
@testable import CharacterKeeperKit

/// Answers requests from a list of rules, in order, and records what was asked.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    typealias Rule = (matches: (URLRequest) -> Bool, respond: () throws -> HTTPResponse)
    private let lock = NSLock()
    private var rules: [Rule] = []
    private(set) var requests: [URLRequest] = []

    func on(_ fragment: String, method: String = "GET", respond: @escaping () throws -> HTTPResponse) {
        lock.withLock {
            rules.append(({ ($0.url?.absoluteString.contains(fragment) ?? false) && $0.httpMethod == method }, respond))
        }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let rule = lock.withLock { () -> Rule? in
            requests.append(request)
            return rules.last { $0.matches(request) }
        }
        guard let rule else { return HTTPResponse(data: Data(), statusCode: 404) }
        return try rule.respond()
    }

    var sentRequests: [URLRequest] { lock.withLock { requests } }
}

private func html(_ text: String) -> HTTPResponse { HTTPResponse(data: Data(text.utf8)) }

struct OrganizedPlayClientTests {
    private let account = Credentials(email: "player@example.com", password: "s3cret pass&")

    private func signedInStub() throws -> StubHTTPClient {
        let stub = StubHTTPClient()
        let summary = try Fixture.text("summary"), page1 = try Fixture.text("sessions-page1")
        let page2 = try Fixture.text("sessions-page2-ajax"), signIn = try Fixture.text("sign-in")
        stub.on("myAccount/player") { html(summary) }
        stub.on("myAccount/allsessions") { html(page1) }
        stub.on("/ajax/") { html(page2) }
        stub.on("DirectAction/signIn") { html(signIn) }
        stub.on("/ajax/", method: "POST") { html("<html></html>") }
        return stub
    }

    @Test func readsTheWholeAccount() async throws {
        let stub = try signedInStub()
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore())
        let snapshot = try await client.fetchAccount()
        #expect(snapshot.characters.count == 9)
        #expect(snapshot.sessions.count == 77)
        let pager = try #require(stub.sentRequests.first { $0.url?.path.contains("/ajax/") == true })
        #expect(pager.url?.query?.hasPrefix("_u=auc_") == true)
        #expect(pager.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
    }

    @Test func signsInWhenAPageAsksForAPassword() async throws {
        let stub = try signedInStub()
        let signIn = try Fixture.text("sign-in"), summary = try Fixture.text("summary")
        var asked = false
        stub.on("myAccount/player") {
            defer { asked = true }
            return html(asked ? summary : signIn)
        }
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore(account))
        #expect(try await client.fetchAccount().characters.count == 9)
        let post = try #require(stub.sentRequests.first { $0.httpMethod == "POST" })
        #expect(post.url?.path.contains("/Store.woa/1/ajax/SESSIONID") == true)
        #expect(post.url?.query?.hasPrefix("_u=SignInPageAjaxSignIn&") == true)
        let body = try #require(String(bytes: post.httpBody ?? Data(), encoding: .utf8))
        #expect(body.contains("e=player%40example.com"))
        #expect(body.contains("zzz=s3cret+pass%26"))
        #expect(body.contains("path=organizedplay%2FmyAccount"))
        #expect(body.contains("AJAX_SUBMIT_BUTTON_NAME=0.1.15.11.3.1.3.2.3.3.7.3.2.1.3.1.1.5"))
    }

    @Test func reportsMissingCredentials() async throws {
        let stub = try signedInStub()
        let signIn = try Fixture.text("sign-in")
        stub.on("myAccount/player") { html(signIn) }
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore())
        await #expect(throws: OrganizedPlayError.noCredentials) { try await client.fetchAccount() }
    }

    @Test func reportsARejectedSignInWithPaizosWords() async throws {
        let stub = try signedInStub()
        let signIn = try Fixture.text("sign-in")
        stub.on("myAccount/player") { html(signIn) }
        stub.on("/ajax/", method: "POST") {
            html(signIn.replacingOccurrences(
                of: "<table cellspacing=\"18\"",
                with: "<div class=\"errorMessage\">Incorrect email or password.</div><table cellspacing=\"18\""))
        }
        let store = InMemoryCredentialStore()
        let client = OrganizedPlayClient(http: stub, credentials: store)
        await #expect(throws: OrganizedPlayError.signInRejected(paizoSays: "Incorrect email or password.")) {
            try await client.signIn(account)
        }
        #expect(store.load() == nil)
    }

    @Test func aSignInThatLeadsNowhereIsASiteChange() async throws {
        let stub = try signedInStub()
        let signIn = try Fixture.text("sign-in")
        stub.on("myAccount/player") { html(signIn) }
        let store = InMemoryCredentialStore()
        let client = OrganizedPlayClient(http: stub, credentials: store)
        let error = await #expect(throws: OrganizedPlayError.self) { try await client.signIn(account) }
        #expect(error.map(FailureMessage.isSiteChange) == true)
        #expect(store.load() == nil)
    }

    @Test func aCaptchaStopsTheSignInBeforeSendingThePassword() async throws {
        let stub = try signedInStub()
        let signIn = try Fixture.text("sign-in")
        stub.on("DirectAction/signIn") { html(signIn + "<div class=\"g-recaptcha\" data-sitekey=\"x\"></div>") }
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore())
        await #expect(throws: OrganizedPlayError.signInChanged(
            reason: "paizo.com now asks for a captcha, which the app can't answer")) {
            try await client.signIn(account)
        }
        #expect(!stub.sentRequests.contains { $0.httpMethod == "POST" })
    }

    @Test func keepsCredentialsThatWork() async throws {
        let store = InMemoryCredentialStore()
        let client = OrganizedPlayClient(http: try signedInStub(), credentials: store)
        try await client.signIn(account)
        #expect(store.load() == account)
    }

    @Test func reportsPagingThatStopsEarly() async throws {
        let stub = try signedInStub()
        stub.on("/ajax/") { html("<html><body><p>Session expired</p></body></html>") }
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore())
        await #expect(throws: OrganizedPlayError.incompletePaging(read: 50, total: 77)) {
            try await client.fetchAccount()
        }
    }

    @Test func reportsHTTPErrors() async throws {
        let stub = try signedInStub()
        stub.on("myAccount/player") { HTTPResponse(data: Data(), statusCode: 503) }
        let client = OrganizedPlayClient(http: stub, credentials: InMemoryCredentialStore())
        await #expect(throws: OrganizedPlayError.http(operation: "Reading the Summary tab", status: 503)) {
            try await client.fetchAccount()
        }
    }

    @Test func errorsDescribeTheProblem() {
        #expect(OrganizedPlayError.incompletePaging(read: 50, total: 77).errorDescription?.contains("50 of 77") == true)
        #expect(OrganizedPlayError.signInRejected(paizoSays: "").errorDescription?.contains("password") == true)
        #expect(OrganizedPlayError.signInRejected(paizoSays: "No such account.").errorDescription?
            .contains("No such account.") == true)
    }

    @Test func signInFormReadsItsFields() throws {
        let form = try SignInFormParser.form(in: Fixture.text("sign-in"))
        #expect(form.emailField == "e")
        #expect(form.passwordField == "zzz")
        #expect(form.containerID == "SignInPageAjaxSignIn")
        #expect(Set(form.hiddenFields.keys) == ["path", "o", "p", "c"])
        #expect(throws: ParsingError.self) { try SignInFormParser.form(in: "<html><form></form></html>") }
    }
}
