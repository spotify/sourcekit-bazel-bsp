load("@aspect_bazel_lib//lib:expand_template.bzl", "expand_template_rule")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application", "ios_unit_test")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application", "macos_command_line_application", "macos_unit_test")
load("@build_bazel_rules_apple//apple:watchos.bzl", "watchos_application", "watchos_extension", "watchos_unit_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_interop_hint", "swift_library")
load("@rules_cc//cc:defs.bzl", "cc_library")
load("@sourcekit_bazel_bsp//rules:setup_sourcekit_bsp.bzl", "setup_sourcekit_bsp")
load("//tools:apple.bzl", "IOS_MINIMUM_OS_VERSION", "WATCHOS_MINIMUM_OS_VERSION", "MACOS_MINIMUM_OS_VERSION")

## MARK: iOS / Shared targets

swift_library(
    name = "HelloWorldTestsLib",
    module_name = "HelloWorldTestsLib",
    testonly = True,
    tags = ["manual"],
    srcs = glob(["HelloWorldTests/*.swift"]),
    deps = [":HelloWorldLib"],
)

swift_library(
    name = "TodoModels",
    module_name = "TodoModels",
    srcs = glob(["TodoModels/Sources/*.swift"]),
)

swift_interop_hint(
    name = "TodoObjCSupport_hint",
    module_name = "TodoObjCSupport",
    module_map = "TodoObjCSupport/Sources/module.modulemap",
)

objc_library(
    name = "TodoObjCSupport",
    srcs = glob(
        [
            "TodoObjCSupport/Sources/*.mm",
            "TodoObjCSupport/Sources/*.m",
        ],
    ),
    hdrs = glob(["TodoObjCSupport/Sources/*.h"]),
    aspect_hints = [":TodoObjCSupport_hint"],
    deps = [":TodoCSupport"],
)

cc_library(
    name = "TodoCSupport",
    srcs = glob(
        [
            "TodoCSupport/src/*.cpp",
            "TodoCSupport/src/*.c",
        ],
    ),
    hdrs = glob(
        [
            "TodoCSupport/include/*.hpp",
            "TodoCSupport/include/*.h",
        ],
    ),
)

swift_library(
    name = "HelloWorldLib",
    module_name = "HelloWorldLib",
    srcs = select({
        "//conditions:default": [],
        ":dbg_mode": glob(["HelloWorldLib/Sources/*.swift"]),
    }),
    deps = [
        ":TodoModelsAlias",
        ":TodoObjCSupport",
        ":ExpandedTemplate",
    ] + select({
        "//conditions:default": [],
        ":dbg_mode": [":GeneratedDummy"],
    }),
)

# Exaggerated alias indirection to show the BSP can follow it
alias(
    name = "TodoModelsAlias",
    actual = ":TodoModelsAlias2",
)
alias(
    name = "TodoModelsAlias2",
    actual = ":TodoModels",
)

# Config to test that the BSP can follow selects in deps and srcs
config_setting(
    name = "dbg_mode",
    values = {"compilation_mode": "dbg"},
)

genrule(
    name = "GenerateDummySwiftFile",
    outs = [
        "GeneratedDummy.swift",
    ],
    cmd = """
cat > $@ << 'EOF'
// This is a generated Swift file
import Foundation

struct GeneratedDummy {
    static let message = "Hello from generated Swift file!"

    static func greet() -> String {
        return message
    }
}
EOF
""",
)

swift_library(
    name = "GeneratedDummy",
    module_name = "GeneratedDummy",
    srcs = [":GenerateDummySwiftFile"],
)

expand_template_rule(
    name = "ExpandTemplateSwiftFile",
    template = "template.swift.tpl",
    out = "ExpandedTemplate.swift",
    substitutions = {
        "{{CLASS_NAME}}": "ExpandedTemplate",
        "{{MESSAGE}}": "Hello from expanded template!",
    },
)

swift_library(
    name = "ExpandedTemplate",
    module_name = "ExpandedTemplate",
    srcs = [":ExpandTemplateSwiftFile"],
)

## MARK: WatchOS targets

swift_library(
    name = "WatchAppTestsLib",
    module_name = "WatchAppTestsLib",
    testonly = True,
    tags = ["manual"],
    srcs = glob(["WatchApp/WatchAppTests/*.swift"]),
    deps = [":WatchAppLib"],
)

swift_library(
    name = "WatchAppLib",
    module_name = "WatchAppLib",
    srcs = glob(["WatchApp/WatchAppLib/Sources/*.swift"]),
    deps = [":TodoModels"],
)

## MARK: MacOS targets

swift_library(
    name = "MacAppTestsLib",
    module_name = "MacAppTestsLib",
    testonly = True,
    srcs = glob(["MacApp/MacAppTests/*.swift"]),
    deps = [":MacAppLib"],
)

swift_library(
    name = "MacAppLib",
    module_name = "MacAppLib",
    srcs = glob(["MacApp/MacAppLib/Sources/*.swift"]),
    deps = [":TodoModels"],
)

## MARK: MacOS CLI targets

swift_library(
    name = "MacCLIAppLib",
    module_name = "MacCLIAppLib",
    srcs = glob(["MacCLIApp/MacCLIAppLib/Sources/*.swift"]),
    deps = [":TodoModels"],
)

## MARK: Top level targets

ios_unit_test(
    name = "HelloWorldTests",
    minimum_os_version = IOS_MINIMUM_OS_VERSION,
    deps = [":HelloWorldTestsLib"],
)

ios_application(
    name = "HelloWorld",
    bundle_id = "com.example.HelloWorld",
    families = ["iphone", "ipad"],
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = IOS_MINIMUM_OS_VERSION,
    deps = [":HelloWorldLib"],
)

watchos_application(
    name = "HelloWorldWatchApp",
    bundle_id = "com.example.HelloWorld.Watch",
    extensions = [":HelloWorldWatchExtension"],
    infoplists = ["Resources/WatchApp-Info.plist"],
    minimum_os_version = WATCHOS_MINIMUM_OS_VERSION,
)

watchos_extension(
    name = "HelloWorldWatchExtension",
    bundle_id = "com.example.HelloWorld.Watch.extension",
    infoplists = ["Resources/WatchExt-Info.plist"],
    minimum_os_version = WATCHOS_MINIMUM_OS_VERSION,
    deps = [":WatchAppLib"],
)

watchos_unit_test(
    name = "HelloWorldWatchTests",
    minimum_os_version = WATCHOS_MINIMUM_OS_VERSION,
    deps = [":WatchAppTestsLib"],
)

macos_application(
    name = "HelloWorldMacApp",
    bundle_id = "com.example.HelloWorld.Mac",
    infoplists = ["Resources/MacApp-Info.plist"],
    minimum_os_version = MACOS_MINIMUM_OS_VERSION,
    deps = [":MacAppLib"],
)

macos_unit_test(
    name = "HelloWorldMacTests",
    minimum_os_version = MACOS_MINIMUM_OS_VERSION,
    deps = [":MacAppTestsLib"],
)

macos_command_line_application(
    name = "HelloWorldMacCLIApp",
    bundle_id = "com.example.HelloWorld.MacCLI",
    infoplists = ["Resources/MacCLIApp-Info.plist"],
    minimum_os_version = MACOS_MINIMUM_OS_VERSION,
    deps = [":MacCLIAppLib"],
)

# Project setup

setup_sourcekit_bsp(
    name = "setup_sourcekit_bsp_example_project",
    bazel_wrapper = "bazelisk",
    files_to_watch = [
        "HelloWorld/**/*.swift",
        "HelloWorld/**/*.h",
        "HelloWorld/**/*.m"
    ],
    index_flags = [
        "config=index_build",
    ],
    index_build_batch_size = 10,
    targets = [
        "//HelloWorld/...",
    ],
)
