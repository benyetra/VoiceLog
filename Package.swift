// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceLog",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VoiceLog", targets: ["VoiceLog"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceLog",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/VoiceLog"
        ),
        .testTarget(
            name: "VoiceLogTests",
            dependencies: ["VoiceLog"],
            path: "Tests/VoiceLogTests"
        ),
    ]
)
