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
            url:
            "https://github.com/swiftlang/swift-tools-protocols",
            revision: "88612c51de4cbf636a6b948c64ea5ebd55b8a0ad"
        ),

        .package(
            url: "https://github.com/apple/swift-argument-parser",
            revision: "1.5.0"
        ),
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            revision: "1.33.3"
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
                    name: "LanguageServerProtocolTransport",
                    package: "swift-tools-protocols"
                ),
                .product(
                    name: "BuildServerProtocol",
                    package: "swift-tools-protocols"
                ),
                .product(
                    name: "ToolsProtocolsSwiftExtensions",
                    package: "swift-tools-protocols"
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
                .copy("Resources/cquery.pb"),
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
            ],
        ),
    ]
)
