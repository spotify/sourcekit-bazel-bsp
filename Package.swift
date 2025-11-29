// swift-tools-version: 6.2

import PackageDescription

// See the same comment in Sources/BUILD.bazel.
// Ideally we would define everything in Bazel
// so that users can make good use of caching and other Bazel features,
// but this currently causes duplication on our end. What we can do instead is once this tool advances
// enough so that we can even run tests from the IDE, we can remove the SPM integration entirely
// and move everything to Bazel, essentially allowing us to using this tool to develop the tool itself
// similarly to how Swift eventually started using Swift itself to build its own compiler.

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
            url: "https://github.com/swiftlang/sourcekit-lsp",
            revision: "0e061c5c1075152bc2e6187679a11b81d0c3e326" // latest main commit November 29, 2025
            // TODO: Ideally it would be better to upstream these changes to sourceKit-lsp
            // url: "https://github.com/rockbruno/sourcekit-lsp",
            // revision: "c052baae81ec6532bb2f939a21acc4650fb1dc86"
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
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                ),
            ],
        ),
        .testTarget(
            name: "SourceKitBazelBSPTests",
            dependencies: [
                "SourceKitBazelBSP",
            ],
            resources: [
                .copy("Resources/aquery.pb"),
                .copy("Resources/streamdeps.pb"),
            ],
        ),
        .target(
            name: "BazelProtobufBindings",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            exclude: [
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
        ),
    ]
)
