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
    name = "HelloWorldLibDep",
    module_name = "HelloWorldLibDep",
    srcs = glob(["HelloWorldLibDep/Sources/*.swift"]),
)

objc_library(
    name = "ObjCDep",
    srcs = glob(
        [
            "ObjCDep/Sources/*.h",
            "ObjCDep/Sources/*.m",
        ],
    ),
    hdrs = glob(["ObjCDep/Sources/*.h"]),
    module_map = "ObjCDep/Sources/module.modulemap",
)

swift_library(
    name = "HelloWorldLib",
    module_name = "HelloWorldLib",
    srcs = glob(["HelloWorldLib/Sources/*.swift"]),
    deps = [":HelloWorldLibDep", ":ObjCDep"],
)

ios_unit_test(
    name = "HelloWorldTests",
    minimum_os_version = "17.5",
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
    minimum_os_version = "17.5",
    deps = [":HelloWorldLib"],
)
