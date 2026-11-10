// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CharacterNotification",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotificationCore"),
        .target(name: "CharacterIconKit"),
        .target(name: "CharacterMediaKit"),
        .testTarget(name: "NotificationCoreTests", dependencies: ["NotificationCore"]),
        .testTarget(name: "CharacterIconKitTests", dependencies: ["CharacterIconKit"]),
        .testTarget(name: "CharacterMediaKitTests", dependencies: ["CharacterMediaKit"])
    ]
)
