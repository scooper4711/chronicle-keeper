// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CharacterKeeper",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CharacterKeeperKit", targets: ["CharacterKeeperKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.14.4")
    ],
    targets: [
        .target(
            name: "CharacterKeeperKit",
            dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")]
        ),
        .testTarget(
            name: "CharacterKeeperKitTests",
            dependencies: ["CharacterKeeperKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
