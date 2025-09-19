load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SourceKitBazelBSP",
    srcs = glob(["**/*.swift"], allow_empty = False),
    module_name = "SourceKitBazelBSP",
    visibility = ["//visibility:public"],
    deps = [
        "//Sources/BazelProtobufBindings",
        "@swiftpkg_sourcekit_lsp//:BuildServerProtocol",
        "@swiftpkg_sourcekit_lsp//:LSPBindings",
        "@swiftpkg_swift_argument_parser//:ArgumentParser",
    ],
    package_name = "sourcekit-bazel-bsp",
)
