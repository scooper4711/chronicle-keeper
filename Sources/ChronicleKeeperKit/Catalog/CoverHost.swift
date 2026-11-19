import Foundation

/// The servers a cover may be loaded from: Paizo's and Warhorn's. Warhorn lists the address of each scenario's
/// cover as whoever entered it typed it, so an address elsewhere is left out rather than sending the player's
/// internet address to a server the privacy policy doesn't name.
public enum CoverHost {
    /// Whether the app may load a cover from this address.
    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        if host == "paizo.com" || host.hasSuffix(".paizo.com") { return true }
        // Paizo's store runs on BigCommerce, whose image server keeps each store's pictures under its own folder.
        if host == "cdn11.bigcommerce.com" { return url.path().hasPrefix("/\(paizoStore)/") }
        return host == "warhorn.imgix.net" || host.firstMatch(of: warhornBucketPattern) != nil
    }

    /// The folder of Paizo's store (store.paizo.com) on BigCommerce's image server.
    static let paizoStore = "s-e0sdfpgiwh"

    // Regex is not Sendable, but this literal is never mutated, so sharing it is safe.

    /// One of Warhorn's own S3 buckets, which imgix serves its uploads from: "warhorn-….s3.amazonaws.com" or
    /// "warhorn-….s3.us-east-1.amazonaws.com".
    nonisolated(unsafe) private static let warhornBucketPattern = /^warhorn[a-z0-9.-]*\.s3[a-z0-9.-]*\.amazonaws\.com$/
}
