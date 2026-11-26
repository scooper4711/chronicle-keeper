import Foundation
import Testing
@testable import ChronicleKeeperKit

/// What the picker offers and what the store does with the choice (R5.10), on `LinkFactory`'s account.
@MainActor
struct AccessLinkOptionsTests {
    private typealias Factory = LinkFactory

    private func options(_ kind: AccessLink.Kind, in store: CharacterStore) throws -> AccessLinkOptions {
        let ryo = try #require(store.roster.characters.first { $0.id == Factory.ryo })
        return AccessLinkOptions(roster: store.roster, buyer: ryo, kind: kind)
    }

    @Test func boonsOfTheSameCampaignAreOfferedTheBuyersFirst() async throws {
        let groups = try options(.boon, in: await Factory.store()).groups
        #expect(groups.map(\.characterName) == ["Ryo Mousehunter", "Korbul Thornbrook"])
        #expect(groups.map { $0.options.map(\.title) } == [["Envoy's Alliance Gear"], ["#6-00: Abendego's Cannon"]])
        #expect(groups.allSatisfy { $0.options.allSatisfy { $0.day == nil && !$0.isTaken } })
    }

    @Test func chronicleSheetsAreTheSameCampaignsSessionsWithTheirDay() async throws {
        let groups = try options(.chronicle, in: await Factory.store()).groups
        #expect(groups.map(\.id) == [Factory.ryo, Factory.korbul])
        let sheet = try #require(groups.first?.options.first)
        #expect(sheet.title == "#6-04: An Enkindled Carnival (1–4)")
        #expect(sheet.day == Date(timeIntervalSince1970: 1_780_000_000))
        #expect(sheet.link.sourceID == "\(Factory.ryo)/1234#1")
    }

    @Test func aLinkedBoonIsTakenAndALinkedChronicleSheetIsNot() async throws {
        let ryo = WealthFactory.record(sessions: 1)
        let sheet = AccessLink(session: ryo.sessions[0].session, of: ryo)
        let store = await Factory.store(purchases: [Factory.korbul: [
            Factory.purchase("shot", linkedTo: AccessLink(boon: Factory.cannon)),
            Factory.purchase("map", linkedTo: sheet)]])
        let boon = try #require(try options(.boon, in: store).groups.last?.options.first)
        #expect(boon.isTaken && boon.uses.summary == "shot (Korbul Thornbrook)")
        #expect(boon.moveQuestion(to: Factory.purchase("gun")) == "#6-00: Abendego's Cannon is linked to shot "
                + "(Korbul Thornbrook). A boon covers one purchase. Move it to gun?")
        let chronicle = try #require(try options(.chronicle, in: store).groups.first?.options.first)
        #expect(!chronicle.isTaken && chronicle.uses.count == 1)
    }

    @Test func aKindThisVersionDoesNotKnowOffersNothingAndIsNeverTaken() async throws {
        let kind = AccessLink.Kind(rawValue: "achievement")
        let link = AccessLink(kind: kind, sourceID: "a1", sourceName: "Master", characterName: "Ryo Mousehunter")
        let store = await Factory.store(purchases: [Factory.ryo: [
            Factory.purchase("a", linkedTo: link), Factory.purchase("b", linkedTo: link)]])
        #expect(try options(kind, in: store).groups.isEmpty)
        let index = store.accessLinks
        #expect(index.uses(of: link).count == 2)
        #expect(index.conflictNote(for: index.uses(of: link)[0]).isEmpty)
    }

    @Test func searchingKeepsACharactersWholeGroupOrTheTitlesThatMatch() async throws {
        let options = try options(.boon, in: await Factory.store())
        #expect(options.groups(matching: " ").count == 2)
        #expect(options.groups(matching: "korbul").map(\.characterName) == ["Korbul Thornbrook"])
        #expect(options.groups(matching: "GEAR").flatMap(\.options).map(\.title) == ["Envoy's Alliance Gear"])
        #expect(options.groups(matching: "nothing").isEmpty)
    }
}

@MainActor
struct AccessLinkStoreTests {
    private typealias Factory = LinkFactory
    private let cannon = AccessLink(boon: LinkFactory.cannon)

    private func link(of id: String, _ number: String, in store: CharacterStore) -> AccessLink? {
        store.settings(for: number).wealth.purchases[id]?.accessLink
    }

    @Test func linkingABoonMovesItFromAnotherCharactersPurchase() async {
        let store = await Factory.store(purchases: [
            Factory.ryo: [Factory.purchase("gun")],
            Factory.korbul: [Factory.purchase("shot", linkedTo: cannon)]])
        var changed: [String] = []
        store.onLocalChange = { changed.append($0) }
        store.link("gun", of: Factory.ryo, to: cannon)
        #expect(link(of: "gun", Factory.ryo, in: store) == cannon)
        #expect(link(of: "shot", Factory.korbul, in: store) == nil)
        #expect(changed == [Factory.korbul, Factory.ryo])
        #expect(store.accessLinks.uses(of: cannon).map(\.id) == ["\(Factory.ryo)/gun"])
    }

    @Test func linkingAChronicleSheetLeavesItsOtherPurchasesLinked() async throws {
        let ryo = WealthFactory.record(sessions: 1)
        let sheet = AccessLink(session: ryo.sessions[0].session, of: ryo)
        let store = await Factory.store(purchases: [
            Factory.ryo: [Factory.purchase("a", linkedTo: sheet), Factory.purchase("b")]])
        store.link("b", of: Factory.ryo, to: sheet)
        #expect(link(of: "a", Factory.ryo, in: store) == sheet && link(of: "b", Factory.ryo, in: store) == sheet)
    }

    @Test func linkingAgainAndUnlinkingChangeOnlyThatPurchase() async {
        let store = await Factory.store(purchases: [Factory.ryo: [Factory.purchase("gun", linkedTo: cannon)]])
        store.link("gun", of: Factory.ryo, to: cannon)
        #expect(link(of: "gun", Factory.ryo, in: store) == cannon)
        store.unlink("gun", of: Factory.ryo)
        #expect(link(of: "gun", Factory.ryo, in: store) == nil)
        #expect(store.accessLinks.uses(of: cannon).isEmpty)
    }
}
