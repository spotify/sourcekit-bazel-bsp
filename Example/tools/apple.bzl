load("@build_bazel_rules_apple//apple:ios.bzl", "ios_build_test")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_build_test")
load("@build_bazel_rules_apple//apple:watchos.bzl", "watchos_build_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

IOS_MINIMUM_OS_VERSION = "17.0"
WATCHOS_MINIMUM_OS_VERSION = "7.0"
MACOS_MINIMUM_OS_VERSION = "15.0"

def hello_swift_library(
    name,
    platforms,
    **kwargs,
):
    swift_library(
        name = name,
        **kwargs,
    )
    if "ios" in platforms:
        ios_build_test(
            name = name + "_ios_skbsp",
            minimum_os_version = IOS_MINIMUM_OS_VERSION,
            targets = [
                name,
            ],
        )
    if "watchos" in platforms:
        watchos_build_test(
            name = name + "_watchos_skbsp",
            minimum_os_version = WATCHOS_MINIMUM_OS_VERSION,
            targets = [
                name,
            ],
        )
    if "macos" in platforms:
        macos_build_test(
            name = name + "_macos_skbsp",
            minimum_os_version = MACOS_MINIMUM_OS_VERSION,
            targets = [
                name,
            ],
        )


def hello_objc_library(
    name,
    platforms,
    **kwargs,
):
    native.objc_library(
        name = name,
        **kwargs,
    )
    if "ios" in platforms:
        ios_build_test(
            name = name + "_ios_skbsp",
            minimum_os_version = IOS_MINIMUM_OS_VERSION,
            targets = [
                name,
            ],
        )
    if "watchos" in platforms:
        watchos_build_test(
            name = name + "_watchos_skbsp",
            minimum_os_version = WATCHOS_MINIMUM_OS_VERSION,
            targets = [
                name,
            ],
        )
    if "macos" in platforms:
        macos_build_test(
            name = name + "_macos_skbsp",
            minimum_os_version = MACOS_MINIMUM_OS_VERSION,
            targets = [
                name,
            ],
        )
