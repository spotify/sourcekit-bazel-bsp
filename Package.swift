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
    ],
    targets: [
        .executableTarget(
            name: "sourcekit-bazel-bsp",
            dependencies: [
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                ),
                .product(
                    name: "BuildServerProtocol",
                    package: "sourcekit-lsp"
                ),
                .product(
                    name: "LSPBindings",
                    package: "sourcekit-lsp"
                ),
            ]
        ),
        .testTarget(
            name: "sourcekit-bazel-bspTests",
            dependencies: [
                "sourcekit-bazel-bsp",
                .product(
                    name: "BuildServerProtocol",
                    package: "sourcekit-lsp"
                ),
                .product(
                    name: "LSPBindings",
                    package: "sourcekit-lsp"
                ),
            ]
        ),
    ]
)
