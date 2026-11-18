import Foundation

/// Everything the app reads from My Organized Play in one refresh.
public struct AccountSnapshot: Codable, Sendable {
    public let characters: [CharacterSummary]
    public let sessions: [PlayedSession]
    public let fetchedAt: Date

    public init(characters: [CharacterSummary], sessions: [PlayedSession], fetchedAt: Date) {
        self.characters = characters
        self.sessions = sessions
        self.fetchedAt = fetchedAt
    }
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
        return AccountSnapshot(characters: characters, sessions: sessions, fetchedAt: Date())
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
        guard let account = credentials.load(), account.isComplete else { throw OrganizedPlayError.noCredentials }
        let reply = try await submitSignIn(account)
        let retry = try await get(url, operation: operation)
        try SignInReply.check(reply: reply, accountPage: retry.text)
        return retry.text
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
