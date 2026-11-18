// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CharacterKeeper",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CharacterKeeperKit", targets: ["CharacterKeeperKit"]),
        .library(name: "CharacterKeeperUI", targets: ["CharacterKeeperUI"]),
        .executable(name: "CharacterKeeper", targets: ["CharacterKeeper"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.14.4"),
        .package(url: "https://github.com/scooper4711/tabletop-kit.git", from: "1.11.0")
    ],
    targets: [
        .target(
            name: "CharacterKeeperKit",
            dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")]
        ),
        .target(
            name: "CharacterKeeperUI",
            dependencies: ["CharacterKeeperKit", .product(name: "AppNotices", package: "tabletop-kit")]
        ),
        // The macOS entry point; the app itself lives in CharacterKeeperUI so the iPad app can share it.
        .executableTarget(name: "CharacterKeeper", dependencies: ["CharacterKeeperUI"]),
        .testTarget(
            name: "CharacterKeeperKitTests",
            dependencies: ["CharacterKeeperKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
