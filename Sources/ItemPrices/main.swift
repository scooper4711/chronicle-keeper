import Foundation
import ItemPriceImport

// Usage: ItemPrices --pf2e <pf2e repository> --out <folder>
let arguments = CommandLine.arguments
func value(of flag: String) -> String? {
    arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
}
guard let repository = value(of: "--pf2e"), let output = value(of: "--out") else {
    FileHandle.standardError.write(Data("usage: ItemPrices --pf2e <pf2e repository> --out <folder>\n".utf8))
    exit(2)
}
do {
    let importer = ItemPriceImporter(repository: URL(fileURLWithPath: repository),
                                     outputDirectory: URL(fileURLWithPath: output))
    let report = try importer.run()
    print("Wrote \(report.itemCount) priced items to \(output)/items.json")
} catch {
    FileHandle.standardError.write(Data("Item price import failed: \(error)\n".utf8))
    exit(1)
}
