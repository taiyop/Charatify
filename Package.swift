// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CharacterNotification",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CharacterNotification", targets: ["CharacterNotification"])],
    targets: [
        .target(name: "NotificationCore"),
        .target(name: "CharacterIconKit"),
        .target(name: "CharacterMediaKit"),
        .executableTarget(name: "CharacterNotification", dependencies: ["NotificationCore", "CharacterIconKit", "CharacterMediaKit"]),
        .testTarget(name: "NotificationCoreTests", dependencies: ["NotificationCore"]),
        .testTarget(name: "CharacterIconKitTests", dependencies: ["CharacterIconKit"]),
        .testTarget(name: "CharacterMediaKitTests", dependencies: ["CharacterMediaKit"])
    ]
)
