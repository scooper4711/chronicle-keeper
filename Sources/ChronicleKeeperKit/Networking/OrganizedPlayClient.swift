import Foundation

/// Everything the app reads from My Organized Play in one refresh.
public struct AccountSnapshot: Codable, Sendable {
    public let characters: [CharacterSummary]
    public let sessions: [PlayedSession]
    public let boons: [Boon]
    public let fetchedAt: Date

    public init(characters: [CharacterSummary], sessions: [PlayedSession], boons: [Boon] = [], fetchedAt: Date) {
        self.characters = characters
        self.sessions = sessions
        self.boons = boons
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey { case characters, sessions, boons, fetchedAt }

    /// Reads a snapshot saved before the app read boons as having none.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            characters: try values.decode([CharacterSummary].self, forKey: .characters),
            sessions: try values.decode([PlayedSession].self, forKey: .sessions),
            boons: try values.decodeIfPresent([Boon].self, forKey: .boons) ?? [],
            fetchedAt: try values.decode(Date.self, forKey: .fetchedAt))
    }
}

/// Where boon PDFs come from: paizo.com, or the demo account.
public protocol BoonSource: Sendable {
    /// The boon's PDF, or nil when the site answers with a page instead, as for a boon the character can't
    /// download yet ("Must have played … to download").
    func pdf(for boon: Boon) async throws -> Data?
}

/// Signs in to paizo.com and reads the player's characters and sessions. It only ever reads.
public actor OrganizedPlayClient {
    private let http: HTTPClient
    private let credentials: CredentialStore
    private let endpoints: OrganizedPlayEndpoints
    /// A guard against a pager that never ends.
    private let maximumPages = 200

    public init(http: HTTPClient, credentials: CredentialStore, endpoints: OrganizedPlayEndpoints = .init()) {
        self.http = http
        self.credentials = credentials
        self.endpoints = endpoints
    }

    /// Signs in with new credentials and keeps them only when paizo.com accepts them.
    public func signIn(_ account: Credentials) async throws {
        let reply = try await submitSignIn(account)
        let check = try await get(endpoints.summaryPage, operation: "Checking the sign-in")
        try SignInReply.check(reply: reply, accountPage: check.text)
        try credentials.save(account)
    }

    public func fetchAccount() async throws -> AccountSnapshot {
        let summary = try await signedInPage(endpoints.summaryPage, operation: "Reading the Summary tab")
        let characters = try SummaryPageParser.characters(in: summary)
        let sessions = try await allSessions()
        let boonsPage = try await signedInPage(endpoints.boonsPage, operation: "Reading the Boons tab")
        let boons = try BoonsPageParser.boons(in: boonsPage, base: endpoints.base)
        return AccountSnapshot(characters: characters, sessions: sessions, boons: boons, fetchedAt: Date())
    }

    // MARK: - Boons

    /// Downloads a boon's PDF, signing in first when paizo.com asks for it.
    public func pdf(for boon: Boon) async throws -> Data? {
        let operation = "Downloading the boon \(boon.name)"
        let response = try await get(boon.downloadURL, operation: operation)
        guard !Self.isPDF(response.data), SignInFormParser.isSignInPage(response.text) else {
            return Self.isPDF(response.data) ? response.data : nil
        }
        let reply = try await submitSignIn(try storedAccount())
        let retry = try await get(boon.downloadURL, operation: operation)
        if Self.isPDF(retry.data) { return retry.data }
        try SignInReply.check(reply: reply, accountPage: retry.text)
        return nil
    }

    static func isPDF(_ data: Data) -> Bool {
        data.starts(with: Data("%PDF".utf8))
    }

    // MARK: - Sessions

    private func allSessions() async throws -> [PlayedSession] {
        let first = try await signedInPage(endpoints.sessionsPage, operation: "Reading the Sessions tab")
        var page = try SessionsPageParser.page(from: first)
        var sessions = page.sessions
        let expectedTotal = page.range?.total
        var pagesRead = 1
        while let next = page.nextPage, page.range?.isLastPage == false, pagesRead < maximumPages {
            let url = endpoints.ajaxUpdate(path: next.path, containerID: next.containerID)
            let operation = "Reading page \(pagesRead + 1) of the Sessions tab"
            let response = try await get(url, operation: operation, ajax: true)
            page = try SessionsPageParser.page(from: response.text)
            sessions += page.sessions
            pagesRead += 1
        }
        try checkComplete(sessions, total: expectedTotal)
        return sessions
    }

    private func checkComplete(_ sessions: [PlayedSession], total: Int?) throws {
        guard let total, sessions.count != total else { return }
        throw OrganizedPlayError.incompletePaging(read: sessions.count, total: total)
    }

    // MARK: - Signing in

    /// A page's HTML, signing in with the stored credentials first when paizo.com asks for them.
    private func signedInPage(_ url: URL, operation: String) async throws -> String {
        let response = try await get(url, operation: operation)
        guard SignInFormParser.isSignInPage(response.text) else { return response.text }
        let reply = try await submitSignIn(try storedAccount())
        let retry = try await get(url, operation: operation)
        try SignInReply.check(reply: reply, accountPage: retry.text)
        return retry.text
    }

    private func storedAccount() throws -> Credentials {
        guard let account = credentials.load(), account.isComplete else { throw OrganizedPlayError.noCredentials }
        return account
    }

    /// Submits the sign-in form and returns paizo.com's answer.
    private func submitSignIn(_ account: Credentials) async throws -> String {
        let page = try await get(endpoints.signInPage, operation: "Opening the sign-in page")
        try SignInReply.checkSupported(signInPage: page.text)
        let form = try SignInFormParser.form(in: page.text)
        let url = endpoints.ajaxUpdate(path: form.ajaxActionPath, containerID: form.containerID)
        let request = URLRequest.postAjaxForm(url, fields: form.fields(for: account))
        return try await http.send(request).validated(operation: "Signing in").text
    }

    private func get(_ url: URL, operation: String, ajax: Bool = false) async throws -> HTTPResponse {
        let request = ajax ? URLRequest.ajaxGet(url) : URLRequest(url: url)
        return try await http.send(request).validated(operation: operation)
    }
}

extension OrganizedPlayClient: BoonSource {}
