import Foundation
import Testing
@testable import ChronicleKeeperKit

struct FailureMessageTests {
    @Test(arguments: [
        ParsingError(operation: "Reading the Summary tab", reason: "there is no character table") as Error,
        OrganizedPlayError.signInChanged(reason: "a new flow"),
        OrganizedPlayError.unexpectedPage(operation: "Reading the Sessions tab"),
        OrganizedPlayError.incompletePaging(read: 50, total: 77),
        OrganizedPlayError.http(operation: "Reading the Summary tab", status: 404),
        OrganizedPlayError.http(operation: "Reading the Summary tab", status: 410)
    ])
    func siteChangesSayWhereToFindAnUpdate(error: Error) {
        #expect(FailureMessage.isSiteChange(error))
        let text = FailureMessage.text(for: error)
        #expect(text.hasPrefix("Paizo's website has changed"))
        #expect(text.hasSuffix(FailureMessage.remedy))
    }

    @Test func aSiteChangeKeepsWhatFailed() {
        let error = ParsingError(operation: "Reading the Summary tab", reason: "there is no character table")
        #expect(FailureMessage.text(for: error).contains("Reading the Summary tab failed: there is no character table"))
    }

    @Test func aRefusalWithoutAReasonMentionsBothCauses() {
        let text = FailureMessage.text(for: OrganizedPlayError.signInRejected(paizoSays: ""))
        #expect(text.contains("email address and password"))
        #expect(text.contains("may have changed"))
        #expect(!FailureMessage.isSiteChange(OrganizedPlayError.signInRejected(paizoSays: "")))
    }

    @Test func aRefusalWithPaizosWordsShowsThem() {
        let text = FailureMessage.text(for: OrganizedPlayError.signInRejected(paizoSays: "Incorrect password."))
        #expect(text == "paizo.com didn't accept the sign-in: “Incorrect password.”")
    }

    @Test func connectionProblemsAreNotSiteChanges() {
        #expect(FailureMessage.text(for: URLError(.notConnectedToInternet)).contains("not connected"))
        #expect(FailureMessage.text(for: URLError(.timedOut)).contains("didn't answer"))
        #expect(!FailureMessage.isSiteChange(URLError(.timedOut)))
        #expect(FailureMessage.text(for: URLError(.badURL)) == URLError(.badURL).localizedDescription)
    }

    @Test func serverErrorsSayToTryLater() {
        let text = FailureMessage.text(for: OrganizedPlayError.http(operation: "Reading the Summary tab", status: 503))
        #expect(text.contains("Try again later"))
        #expect(FailureMessage.text(for: OrganizedPlayError.noCredentials) == "Sign in to paizo.com first.")
    }
}

struct SignInReplyTests {
    private let signedIn = "<html><body><table class=\"characters\"></table></body></html>"
    private let form = "<form><input type=\"password\" name=\"zzz\"></form>"

    @Test func anAccountPageMeansSignedIn() throws {
        try SignInReply.check(reply: "<html></html>", accountPage: signedIn)
    }

    @Test func theFormAgainIsARefusal() {
        #expect(throws: OrganizedPlayError.signInRejected(paizoSays: "")) {
            try SignInReply.check(reply: form, accountPage: form)
        }
    }

    @Test(arguments: [
        "<span class=\"error\">Wrong password</span>", "<font color=red>Wrong password</font>",
        "<div id=\"loginError\"> Wrong password </div>", "<p style=\"color: red\">Wrong password</p>"
    ])
    func findsPaizosErrorText(markup: String) {
        #expect(SignInReply.errorText(in: form + markup) == "Wrong password")
    }

    @Test func noFormAndNoAccountIsAChange() {
        #expect(throws: OrganizedPlayError.self) {
            try SignInReply.check(reply: "<script>window.location='/mfa'</script>", accountPage: form)
        }
    }

    @Test(arguments: ["g-recaptcha", "h-captcha", "cf-turnstile"])
    func captchasAreNotSupported(marker: String) {
        #expect(throws: OrganizedPlayError.self) {
            try SignInReply.checkSupported(signInPage: "<div class=\"\(marker)\"></div>")
        }
    }

    @Test(arguments: ["type=\"password\"", "type='password'", "TYPE=password ", "type = \"password\""])
    func recognizesThePasswordFieldHoweverItIsWritten(attribute: String) {
        #expect(SignInFormParser.isSignInPage("<input \(attribute) name=\"zzz\">"))
        #expect(!SignInFormParser.isSignInPage("<input type=\"passwordless\">"))
    }
}
