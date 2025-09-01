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
            revision: "1aae2a4c329035163db85d64ae7bc81ee80aaa3c"
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
            ],
            exclude: [
                "BUILD",
            ]
        ),
        .target(
            name: "SourceKitBazelBSP",
            dependencies: [
                "BazelProtobufBindings",
                .product(
                    name: "BuildServerProtocol",
                    package: "sourcekit-lsp"
                ),
                .product(
                    name: "LSPBindings",
                    package: "sourcekit-lsp"
                ),
            ],
            exclude: [
                "BUILD",
            ]
        ),
        .testTarget(
            name: "SourceKitBazelBSPTests",
            dependencies: ["SourceKitBazelBSP"],
            resources: [
                .copy("Resources/aquery.pb"),
                .copy("Resources/aquery_objc.pb"),
                .copy("Resources/streamdeps.pb"),
            ],
        ),
        .target(
            name: "BazelProtobufBindings",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            exclude: [
                "BUILD",
                "README.md",
                "protos/analysis_v2.proto",
                "protos/build.proto",
                "protos/stardoc_output.proto",
            ]
        ),
        .testTarget(
            name: "BazelProtobufBindingsTests",
            dependencies: ["BazelProtobufBindings"],
            resources: [
                .copy("Resources/actions.pb"),
                .copy("Resources/streamdeps.pb"),
            ],
        )
    ]
)
