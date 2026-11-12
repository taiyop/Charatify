// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Charatify",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Charatify", targets: ["Charatify"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1")
    ],
    targets: [
        .target(name: "AppConfiguration"),
        .target(name: "NotificationCore"),
        .target(name: "CharacterIconKit"),
        .target(name: "CharacterMediaKit"),
        .executableTarget(
            name: "Charatify",
            dependencies: [
                "AppConfiguration", "NotificationCore", "CharacterIconKit", "CharacterMediaKit",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "AppConfigurationTests", dependencies: ["AppConfiguration", "CharacterMediaKit"]),
        .testTarget(name: "NotificationCoreTests", dependencies: ["NotificationCore"]),
        .testTarget(name: "CharacterIconKitTests", dependencies: ["CharacterIconKit"]),
        .testTarget(name: "CharacterMediaKitTests", dependencies: ["CharacterMediaKit"])
    ]
)
