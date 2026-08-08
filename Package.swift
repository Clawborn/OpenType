// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenType",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OpenType", targets: ["OpenType"])
    ],
    targets: [
        .executableTarget(
            name: "OpenType",
            path: "Sources/OpenType",
            swiftSettings: [
                .define("OPENTYPE_APP")
            ]
        ),
        .testTarget(
            name: "OpenTypeTests",
            dependencies: ["OpenType"],
            path: "Tests/OpenTypeTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
