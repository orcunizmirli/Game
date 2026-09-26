// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GameCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .executable(name: "levelcheck", targets: ["levelcheck"]),
    ],
    targets: [
        .target(
            name: "GameCore",
            resources: [.copy("Levels")]
        ),
        .executableTarget(
            name: "levelcheck",
            dependencies: ["GameCore"]
        ),
        .testTarget(
            name: "GameCoreTests",
            dependencies: ["GameCore"]
        ),
    ]
)
