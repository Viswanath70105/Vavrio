// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Vavrio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vavrio", targets: ["Vavrio"])
    ],
    targets: [
        .executableTarget(name: "Vavrio"),
        .testTarget(name: "VavrioTests", dependencies: ["Vavrio"])
    ],
    swiftLanguageModes: [.v6]
)
