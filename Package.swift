// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "sourcekit-bazel-bsp",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            revision: "1.5.0"
        ),
        .package(
            url: "https://github.com/apple/sourcekit-lsp",
            revision: "12da8e5f54809b642701dd0dd6e145d3e0c67bc4"
        ),
        .package(
            url: "https://github.com/apple/swift-log",
            revision: "3d8596ed08bd13520157f0355e35caed215ffbfa"
        ),
    ],
    targets: [
        .executableTarget(
            name: "sourcekit-bazel-bsp",
            dependencies: [
                "SourceKitBazelBSP",
                "BSPLogging",
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                ),
            ]
        ),
        .target(
            name: "SourceKitBazelBSP",
            dependencies: [
                "BSPLogging",
                .product(
                    name: "BuildServerProtocol",
                    package: "sourcekit-lsp"
                ),
                .product(
                    name: "LSPBindings",
                    package: "sourcekit-lsp"
                ),
            ],
        ),
        .testTarget(
            name: "SourceKitBazelBSPTests",
            dependencies: ["SourceKitBazelBSP"]
        ),
        .target(
            name: "BSPLogging",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        ),
    ]
)
