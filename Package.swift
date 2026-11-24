// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChronicleKeeper",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ChronicleKeeperKit", targets: ["ChronicleKeeperKit"]),
        .library(name: "ChronicleKeeperUI", targets: ["ChronicleKeeperUI"]),
        .executable(name: "ChronicleKeeper", targets: ["ChronicleKeeper"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.14.4"),
        .package(url: "https://github.com/scooper4711/tabletop-kit.git", from: "1.19.0")
    ],
    targets: [
        .target(
            name: "ChronicleKeeperKit",
            dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")],
            resources: [.copy("Resources/adventure-covers.json")]
        ),
        .target(
            name: "ChronicleKeeperUI",
            dependencies: ["ChronicleKeeperKit", .product(name: "AppNotices", package: "tabletop-kit")],
            resources: [.copy("Resources/Factions")]
        ),
        // The macOS entry point; the app itself lives in ChronicleKeeperUI so the iPad app can share it.
        .executableTarget(name: "ChronicleKeeper", dependencies: ["ChronicleKeeperUI"]),
        .testTarget(
            name: "ChronicleKeeperKitTests",
            dependencies: ["ChronicleKeeperKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
