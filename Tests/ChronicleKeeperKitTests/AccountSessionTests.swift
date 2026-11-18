import Foundation
import Testing
@testable import ChronicleKeeperKit

@MainActor
struct AccountSessionTests {
    private let account = Credentials(email: "player@example.com", password: "s3cret")

    /// paizo.com as the stub answers it: `acceptsSignIn` decides whether the account pages come back after signing in.
    private func live(
        acceptsSignIn: Bool, credentials: CredentialStore = InMemoryCredentialStore()
    ) throws -> AccountSession.LiveAccount {
        let stub = StubHTTPClient()
        let summary = try Fixture.text("summary"), signIn = try Fixture.text("sign-in")
        let page1 = try Fixture.text("sessions-page1"), page2 = try Fixture.text("sessions-page2-ajax")
        let accountPage = acceptsSignIn ? summary : signIn
        stub.on("myAccount/player") { HTTPResponse(data: Data(accountPage.utf8)) }
        stub.on("myAccount/allsessions") { HTTPResponse(data: Data(page1.utf8)) }
        let boons = try Fixture.text("boons")
        stub.on("myAccount/rewards") { HTTPResponse(data: Data(boons.utf8)) }
        stub.on("/ajax/") { HTTPResponse(data: Data(page2.utf8)) }
        stub.on("DirectAction/signIn") { HTTPResponse(data: Data(signIn.utf8)) }
        // A refused sign-in shows the form again; an accepted one answers with something else.
        let reply = acceptsSignIn ? "<html></html>" : signIn
        stub.on("/ajax/", method: "POST") { HTTPResponse(data: Data(reply.utf8)) }
        return AccountSession.LiveAccount(
            client: OrganizedPlayClient(http: stub, credentials: credentials),
            credentials: credentials, repository: InMemoryCharacterRepository())
    }

    @Test func startsSignedOutWithoutSavedCredentials() throws {
        let session = AccountSession(live: try live(acceptsSignIn: true))
        #expect(session.mode == .signedOut)
        #expect(!session.canRefresh)
    }

    @Test func startsSignedInWithSavedCredentials() throws {
        let session = AccountSession(live: try live(acceptsSignIn: true, credentials: InMemoryCredentialStore(account)))
        #expect(session.mode == .signedIn(email: "player@example.com"))
        #expect(session.canRefresh)
    }

    @Test func signingInReadsTheAccount() async throws {
        let credentials = InMemoryCredentialStore()
        let session = AccountSession(live: try live(acceptsSignIn: true, credentials: credentials))
        await session.signIn(account)
        #expect(session.mode == .signedIn(email: "player@example.com"))
        #expect(session.signInError == nil)
        #expect(session.store.roster.characters.count == 9)
        #expect(credentials.load() == account)
    }

    @Test func aRejectedSignInStaysSignedOutAndSaysWhy() async throws {
        let credentials = InMemoryCredentialStore()
        let session = AccountSession(live: try live(acceptsSignIn: false, credentials: credentials))
        await session.signIn(account)
        #expect(session.mode == .signedOut)
        #expect(session.signInError == FailureMessage.text(for: OrganizedPlayError.signInRejected(paizoSays: "")))
        #expect(session.signInError?.contains(FailureMessage.remedy) == true)
        #expect(credentials.load() == nil)
    }

    @Test func signingOutForgetsThePasswordAndTheAccount() async throws {
        let credentials = InMemoryCredentialStore()
        let session = AccountSession(live: try live(acceptsSignIn: true, credentials: credentials))
        await session.signIn(account)
        session.signOut()
        #expect(session.mode == .signedOut)
        #expect(credentials.load() == nil)
        #expect(session.store.roster.characters.isEmpty)
    }

    @Test func theDemoShowsTheDemoAccountAndLeavesAgain() async throws {
        let session = AccountSession(live: try live(acceptsSignIn: true, credentials: InMemoryCredentialStore(account)))
        session.startDemo()
        #expect(session.isDemo)
        await session.store.refresh()
        #expect(session.store.roster.characters.count == DemoAccount.characters.count)
        session.leaveDemo()
        #expect(session.mode == .signedIn(email: "player@example.com"))
    }

    @Test func leavingTheDemoWithoutAnAccountShowsSignedOut() throws {
        let session = AccountSession(live: try live(acceptsSignIn: true))
        session.leaveDemo()
        #expect(session.mode == .signedOut)
        session.startDemo()
        session.leaveDemo()
        #expect(session.mode == .signedOut)
    }
}

struct DemoAccountTests {
    @Test func everyDemoSessionBelongsToADemoCharacter() {
        let snapshot = DemoAccount.snapshot()
        let roster = CharacterRoster(summaries: snapshot.characters, sessions: snapshot.sessions)
        #expect(roster.unmatchedSessions.isEmpty)
        #expect(roster.characters.allSatisfy { $0.summary.number.hasPrefix(DemoAccount.playerNumber) })
    }

    @Test func theDemoShowsEveryKindOfRow() {
        let sessions = DemoAccount.snapshot().sessions
        #expect(sessions.contains { $0.isGameMaster })
        #expect(sessions.contains { $0.reputation == nil })
        let kinds = Set(sessions.map { AdventureClassifier.kind(of: $0.adventure) })
        #expect(kinds.isSuperset(of: [.scenario, .questSeries2, .bounty]))
    }

    @Test func anAdventureKeepsOneProductIDAcrossCharacters() {
        let lanternFair = DemoAccount.snapshot().sessions.filter { $0.adventure.title.contains("Lantern Fair") }
        #expect(lanternFair.count == 2)
        #expect(Set(lanternFair.map(\.adventure.productID)).count == 1)
    }
}

@MainActor
struct CharacterStoreAttemptTests {
    private struct Failure: Error, LocalizedError {
        var errorDescription: String? { "Saving the portrait failed: disk full" }
    }

    @Test func attemptReturnsTheValueOrShowsTheError() {
        let store = CharacterStore(repository: InMemoryCharacterRepository()) { DemoAccount.snapshot() }
        #expect(store.attempt { 42 } == 42)
        #expect(store.errorMessage == nil)
        #expect(store.attempt { () throws -> Int in throw Failure() } == nil)
        #expect(store.errorMessage == "Saving the portrait failed: disk full")
    }
}
