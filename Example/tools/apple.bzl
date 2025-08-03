load("@build_bazel_rules_apple//apple:ios.bzl", "ios_build_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

IOS_MINIMUM_OS_VERSION = "17.0"

def hello_swift_library(
    name,
    **kwargs,
):
    swift_library(
        name = name,
        **kwargs,
    )
    ios_build_test(
        name = name + "_skbsp_ios",
        minimum_os_version = IOS_MINIMUM_OS_VERSION,
        targets = [
            name,
        ],
    )


def hello_objc_library(
    name,
    **kwargs,
):
    native.objc_library(
        name = name,
        **kwargs,
    )
    ios_build_test(
        name = name + "_skbsp_ios",
        minimum_os_version = IOS_MINIMUM_OS_VERSION,
        targets = [
            name,
        ],
    )
