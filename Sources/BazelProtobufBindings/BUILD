load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "BazelProtobufBindings",
    srcs = glob(["**/*.swift"], allow_empty = False),
    module_name = "BazelProtobufBindings",
    visibility = ["//visibility:public"],
    deps = [
        "@swiftpkg_swift_protobuf//:SwiftProtobuf",
    ],
    package_name = "BazelProtobufBindings",
)
