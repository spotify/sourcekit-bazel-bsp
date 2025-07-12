load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application", "ios_unit_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:defs.bzl", "objc_library")


swift_library(
    name = "HelloWorldTestsLib",
    module_name = "HelloWorldTestsLib",
    testonly = True,
    srcs = glob(["HelloWorldTests/*.swift"]),
    deps = [":HelloWorldLib"],
)

swift_library(
    name = "TodoModels",
    module_name = "TodoModels",
    srcs = glob(["TodoModels/Sources/*.swift"]),
)

objc_library(
    name = "TodoObjCSupport",
    srcs = glob(
        [
            "TodoObjCSupport/Sources/*.h",
            "TodoObjCSupport/Sources/*.m",
        ],
    ),
    hdrs = glob(["TodoObjCSupport/Sources/*.h"]),
    module_map = "TodoObjCSupport/Sources/module.modulemap",
)

swift_library(
    name = "HelloWorldLib",
    module_name = "HelloWorldLib",
    srcs = glob(["HelloWorldLib/Sources/*.swift"]),
    deps = [":TodoModels", ":TodoObjCSupport"],
)

ios_unit_test(
    name = "HelloWorldTests",
    minimum_os_version = "18.4",
    bundle_id = "com.example.HelloWorldTests",
    platform_type = "ios",
    test_host = ":HelloWorld",
    deps = [":HelloWorldTestsLib"],
)

ios_application(
    name = "HelloWorld",
    bundle_id = "com.example.HelloWorld",
    families = [
        "iphone",
    ],
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "18.4",
    deps = [":HelloWorldLib"],
)
