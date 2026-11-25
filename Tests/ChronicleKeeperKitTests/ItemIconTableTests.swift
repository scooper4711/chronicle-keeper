import Testing
@testable import ChronicleKeeperKit

struct ItemIconTableTests {
    private let table = ItemIconTable(tsv: """
        item\trexard\ticon
        pf2e/abc\tpack/Swords/sword 1.png\tpack_Swords_sword-1.heic
        sf2e/xyz\tpack/Guns/laser.png\tpack_Guns_laser.heic
        broken row
        pf2e/empty\tpack/x.png\t

        """)

    @Test func anItemFindsItsIcon() {
        #expect(table.icon(for: "pf2e/abc") == "pack_Swords_sword-1.heic")
        #expect(table.icon(for: "sf2e/xyz") == "pack_Guns_laser.heic")
    }

    @Test func customItemsAndRowsWithoutAnIconHaveNone() {
        #expect(table.icon(for: "") == nil)
        #expect(table.icon(for: "pf2e/unknown") == nil)
        #expect(table.icon(for: "pf2e/empty") == nil)
        #expect(table.count == 2)
    }
}
