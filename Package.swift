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
            revision: "5df8f3d9ac0e647238ed4203e8f399ae5a095aa3"
        ),
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            revision: "102a647b573f60f73afdce5613a51d71349fe507"
        ),
    ],
    targets: [
        .executableTarget(
            name: "sourcekit-bazel-bsp",
            dependencies: [
                "SourceKitBazelBSP",
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                ),
            ]
        ),
        .target(
            name: "SourceKitBazelBSP",
            dependencies: [
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
            name: "BazelProtobufBindings",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            exclude: [
                "README.md",
                "analysis_v2.proto",
            ]
        ),
        .testTarget(
            name: "BazelProtobufBindingsTests",
            dependencies: ["BazelProtobufBindings"],
            resources: [
                .copy("Resources/actions.pb")
            ],
        )
    ]
)
