import Foundation
import Testing
@testable import ChronicleKeeperKit

/// An account with two Pathfinder characters and a Starfinder one, each with a boon and a session, for linking
/// purchases to boons and Chronicle Sheets (R5.10).
enum LinkFactory {
    static let ryo = "123456-2001"
    static let korbul = "123456-2002"
    static let zix = "123456-701"

    static let cannon = boon("#6-00: Abendego's Cannon", of: "Korbul Thornbrook", reward: "r1")
    static let gear = boon("Envoy's Alliance Gear", of: "Ryo Mousehunter", reward: "r2")
    static let beacon = boon("Drift Beacon", of: "Zix-7", reward: "r3")

    static func boon(_ name: String, of character: String, reward: String) -> Boon {
        var fields = BoonFields()
        fields.characterName = character
        fields.name = name
        fields.downloadURL = URL(string: "https://example.com/boon?character=\(character.count)&reward=\(reward)")
            ?? URL(fileURLWithPath: "/")
        return Boon(fields: fields)
    }

    static func snapshot() -> AccountSnapshot {
        AccountSnapshot(
            characters: [
                summary(zix, "Zix-7", .starfinder2), summary(korbul, "Korbul Thornbrook", .pathfinder2),
                summary(ryo, "Ryo Mousehunter", .pathfinder2)],
            sessions: [
                session("#6-04: An Enkindled Carnival", number: 1, of: "Ryo Mousehunter", ryo),
                session("#6-00: Abendego's Cannon", number: 2, of: "Korbul Thornbrook", korbul),
                session("#1-03: Static on the Drift", number: 3, of: "Zix-7", zix)],
            boons: [cannon, gear, beacon], fetchedAt: Date(timeIntervalSince1970: 1_780_000_000))
    }

    /// A store holding the account, with these purchases in the characters' ledgers.
    @MainActor
    static func store(purchases: [String: [Purchase]] = [:]) async -> CharacterStore {
        let settings = purchases.mapValues { purchases in
            var settings = CharacterSettings()
            purchases.forEach { settings.wealth.add($0) }
            return settings
        }
        let store = CharacterStore(repository: InMemoryCharacterRepository(settings: settings)) { snapshot() }
        store.load()
        await store.refresh()
        return store
    }

    static func purchase(_ id: String, linkedTo link: AccessLink? = nil) -> Purchase {
        var purchase = WealthFactory.purchase(id, price: 100, rarity: .uncommon)
        purchase.accessLink = link
        return purchase
    }

    private static func summary(_ number: String, _ name: String, _ campaign: Campaign) -> CharacterSummary {
        CharacterSummary(number: number, campaign: campaign, name: name, factions: [], standing: [])
    }

    private static func session(_ title: String, number: Int, of name: String, _ player: String) -> PlayedSession {
        SessionFactory.session(title: title, sessionNumber: number, characterName: name, playerNumber: player)
    }
}

struct AccessLinkTests {
    private let boonLink = AccessLink(boon: LinkFactory.cannon)

    @Test func aBoonLinkCopiesTheBoonsIDAndNames() {
        #expect(boonLink.kind == .boon && boonLink.sourceID == LinkFactory.cannon.id)
        #expect(boonLink.sourceDescription == "Korbul Thornbrook's boon #6-00: Abendego's Cannon")
    }

    @Test func aChronicleLinkNamesTheSessionByItsCharactersNumber() {
        let record = WealthFactory.record(sessions: 1)
        let link = AccessLink(session: record.sessions[0].session, of: record)
        #expect(link.kind == .chronicle && link.sourceID == "123456-2001/1234#1")
        #expect(link.sourceDescription == "Valeria Stonebrook's Chronicle Sheet for #6-04: An Enkindled Carnival")
        #expect(link.key != AccessLink(kind: .boon, sourceID: link.sourceID, sourceName: "", characterName: "").key)
    }

    @Test func aPurchaseKeepsItsLinkThroughSavingAndWhatANewerVersionAddedToIt() throws {
        let json = """
            {"id":"x","name":"Cannon","unitPrice":5,"accessLink":{"kind":"boon","sourceID":"c1/r1",\
            "sourceName":"Abendego's Cannon","characterName":"Korbul Thornbrook","grants":["cannon"]}}
            """
        let purchase = try JSONDecoder().decode(Purchase.self, from: Data(json.utf8))
        #expect(purchase.accessLink?.sourceID == "c1/r1")
        #expect(purchase.accessLink?.unknownFields.values["grants"] == .array([.string("cannon")]))
        let again = try JSONDecoder().decode(Purchase.self, from: JSONEncoder().encode(purchase))
        #expect(again == purchase)
    }

    @Test func aPurchaseSavedWithoutALinkHasNone() throws {
        let saved = try JSONEncoder().encode(WealthFactory.purchase("rope", price: 1))
        #expect(String(bytes: saved, encoding: .utf8)?.contains("accessLink") == false)
        #expect(try JSONDecoder().decode(Purchase.self, from: saved).accessLink == nil)
    }

    @Test func sellingKeepsTheLinkAndUnlinkingRemovesIt() {
        var wealth = CharacterWealth()
        wealth.add(WealthFactory.purchase("cannon", price: 100))
        wealth.link("cannon", to: boonLink)
        wealth.sell("cannon", after: "", in: LedgerOrder(keys: []))
        #expect(wealth.purchases["cannon"]?.accessLink == boonLink)
        wealth.unlink("cannon")
        #expect(wealth.purchases["cannon"]?.accessLink == nil)
    }

    @Test func twoDevicesLinkingOneBoonBothKeepTheirLink() {
        let mine = CharacterWealth(purchases: ["a": LinkFactory.purchase("a", linkedTo: boonLink),
                                               "b": LinkFactory.purchase("b")])
        let theirs = CharacterWealth(purchases: ["a": LinkFactory.purchase("a"),
                                                 "b": LinkFactory.purchase("b", linkedTo: boonLink)])
        let ancestor = CharacterWealth(purchases: ["a": LinkFactory.purchase("a"), "b": LinkFactory.purchase("b")])
        let merged = WealthMerge.merge(local: mine, remote: theirs, ancestor: ancestor)
        #expect(merged.purchases.values.compactMap(\.accessLink) == [boonLink, boonLink])
    }
}

struct LinkedLegalityTests {
    private let link = AccessLink(boon: LinkFactory.cannon)

    @Test func aWarningGivesEachReason() {
        let text = PurchaseLegality.warning(for: [.notCommon(.uncommon)])
        #expect(text == "This purchase may not be Society legal. "
                + "Uncommon: needs Access, such as from a boon or a Chronicle Sheet.")
    }

    @Test func aLinkSaysWhatItWaivesAndWhoseItIs() {
        let marks: [LegalityMark] = [.aboveLevel(itemLevel: 5, limit: 2), .notCommon(.rare)]
        let text = PurchaseLegality.explanation(of: marks, coveredBy: link)
        #expect(text == "Level 5: above the highest item level the character could buy here (2), allowed by "
                + "Korbul Thornbrook's boon #6-00: Abendego's Cannon. "
                + "Rare: Access from Korbul Thornbrook's boon #6-00: Abendego's Cannon.")
    }

    @Test func aLinkOnAPurchaseWithoutMarksOnlyNamesItself() {
        #expect(PurchaseLegality.explanation(of: [], coveredBy: link)
                == "Linked to Korbul Thornbrook's boon #6-00: Abendego's Cannon.")
    }
}

@MainActor
struct AccessLinkIndexTests {
    private typealias Factory = LinkFactory
    private let cannon = AccessLink(boon: LinkFactory.cannon)

    private func use(_ id: String, of number: String, in store: CharacterStore) throws -> AccessLinkUse {
        let record = try #require(store.roster.characters.first { $0.id == number })
        let purchase = try #require(record.settings.wealth.purchases[id])
        return AccessLinkUse(characterNumber: number, characterName: record.name, purchase: purchase)
    }

    @Test func itFindsABoonsPurchaseOnAnyCharacter() async {
        let store = await Factory.store(purchases: [Factory.ryo: [Factory.purchase("gun", linkedTo: cannon)]])
        let uses = store.accessLinks.uses(of: cannon)
        #expect(uses.map(\.id) == ["\(Factory.ryo)/gun"])
        #expect(uses.summary == "gun (Ryo Mousehunter)")
        #expect(store.accessLinks.uses(of: AccessLink(boon: Factory.gear)).isEmpty)
    }

    @Test func aBoonLinkedTwiceSaysSoOnBothPurchases() async throws {
        let store = await Factory.store(purchases: [
            Factory.ryo: [Factory.purchase("gun", linkedTo: cannon)],
            Factory.korbul: [Factory.purchase("shot", linkedTo: cannon)]])
        let index = store.accessLinks
        #expect(index.conflictNote(for: try use("gun", of: Factory.ryo, in: store))
                == "This boon is also linked to shot (Korbul Thornbrook). "
                + "A boon covers one purchase, so unlink one of them.")
        #expect(index.conflictNote(for: try use("shot", of: Factory.korbul, in: store)).contains("gun (Ryo"))
    }

    @Test func aBoonLinkedOnceAndASharedChronicleSheetHaveNoNote() async throws {
        let ryo = WealthFactory.record(sessions: 1)
        let sheet = AccessLink(session: ryo.sessions[0].session, of: ryo)
        let store = await Factory.store(purchases: [Factory.ryo: [
            Factory.purchase("gun", linkedTo: cannon), Factory.purchase("a", linkedTo: sheet),
            Factory.purchase("b", linkedTo: sheet), Factory.purchase("plain")]])
        let index = store.accessLinks
        #expect(index.uses(of: sheet).count == 2)
        for id in ["gun", "a", "b", "plain"] {
            #expect(index.conflictNote(for: try use(id, of: Factory.ryo, in: store)).isEmpty)
        }
    }
}

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
