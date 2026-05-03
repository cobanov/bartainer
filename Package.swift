// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Bartainer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Bartainer", targets: ["Bartainer"])
    ],
    targets: [
        .executableTarget(
            name: "Bartainer",
            path: "Sources/BartainerApp"
        )
    ]
)
