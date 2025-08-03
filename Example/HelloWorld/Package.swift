// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HelloWorld",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "HelloWorldLib",
            targets: ["HelloWorldLib"]
        ),
        .library(
            name: "TodoModels",
            targets: ["TodoModels"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/iwasrobbed/Down", from: "0.11.0"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "HelloWorldLib",
            dependencies: ["TodoModels", "Down", "Kingfisher"],
            path: "HelloWorldLib/Sources"
        ),
        .target(
            name: "TodoModels",
            dependencies: [],
            path: "TodoModels/Sources"
        ),
        .testTarget(
            name: "HelloWorldTests",
            dependencies: ["HelloWorldLib", "TodoModels"],
            path: "HelloWorldTests"
        ),
    ]
)
