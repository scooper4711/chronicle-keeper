import Foundation

/// Linking purchases to the boons and Chronicle Sheets that make them legal (R5.10).
extension CharacterStore {
    /// Where every boon and Chronicle Sheet is used, across all characters.
    public var accessLinks: AccessLinkIndex {
        AccessLinkIndex(characters: roster.characters)
    }

    /// Links one of a character's purchases to a boon or Chronicle Sheet. A boon covers one purchase, so one that
    /// is linked elsewhere, on any character, is moved here; a Chronicle Sheet stays with the others it covers.
    public func link(_ purchaseID: String, of characterNumber: String, to link: AccessLink) {
        let target = "\(characterNumber)/\(purchaseID)"
        if link.kind == .boon {
            for use in accessLinks.uses(of: link) where use.id != target {
                update(use.characterNumber) { $0.wealth.unlink(use.purchase.id) }
            }
        }
        update(characterNumber) { $0.wealth.link(purchaseID, to: link) }
    }

    /// Takes the link off a purchase, which brings its marks back.
    public func unlink(_ purchaseID: String, of characterNumber: String) {
        update(characterNumber) { $0.wealth.unlink(purchaseID) }
    }
}
