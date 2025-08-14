load("@build_bazel_rules_swift//swift:swift.bzl", "swift_binary")

swift_binary(
    name = "sourcekit-bazel-bsp",
    srcs = glob(["**/*.swift"], allow_empty = False),
    deps = [
        "//Sources/SourceKitBazelBSP",
        "@swiftpkg_swift_argument_parser//:ArgumentParser",
        "@swiftpkg_swift_protobuf//:SwiftProtobuf",
    ],
    visibility = ["//visibility:public"],
)
