// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Charatify",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Charatify", targets: ["Charatify"])],
    targets: [
        .target(name: "NotificationCore"),
        .target(name: "CharacterIconKit"),
        .target(name: "CharacterMediaKit"),
        .executableTarget(name: "Charatify", dependencies: ["NotificationCore", "CharacterIconKit", "CharacterMediaKit"]),
        .testTarget(name: "NotificationCoreTests", dependencies: ["NotificationCore"]),
        .testTarget(name: "CharacterIconKitTests", dependencies: ["CharacterIconKit"]),
        .testTarget(name: "CharacterMediaKitTests", dependencies: ["CharacterMediaKit"])
    ]
)
