load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application", "ios_unit_test")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application", "macos_unit_test")
load("@build_bazel_rules_apple//apple:watchos.bzl", "watchos_application", "watchos_extension", "watchos_unit_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_interop_hint")
load("@aspect_bazel_lib//lib:expand_template.bzl", "expand_template_rule")
load("//tools:apple.bzl", "hello_objc_library", "hello_swift_library", "IOS_MINIMUM_OS_VERSION", "WATCHOS_MINIMUM_OS_VERSION", "MACOS_MINIMUM_OS_VERSION")

## MARK: iOS / Shared targets

hello_swift_library(
    name = "HelloWorldTestsLib",
    module_name = "HelloWorldTestsLib",
    testonly = True,
    tags = ["manual"],
    srcs = glob(["HelloWorldTests/*.swift"]),
    deps = [":HelloWorldLib"],
    platforms = ["ios"],
)

hello_swift_library(
    name = "TodoModels",
    module_name = "TodoModels",
    srcs = glob(["TodoModels/Sources/*.swift"]),
    platforms = ["ios", "watchos", "macos"],
)

swift_interop_hint(
    name = "TodoObjCSupport_hint",
    module_name = "TodoObjCSupport",
    module_map = "TodoObjCSupport/Sources/module.modulemap",
)

hello_objc_library(
    name = "TodoObjCSupport",
    srcs = glob(
        [
            "TodoObjCSupport/Sources/*.h",
            "TodoObjCSupport/Sources/*.m",
        ],
    ),
    hdrs = glob(["TodoObjCSupport/Sources/*.h"]),
    aspect_hints = [":TodoObjCSupport_hint"],
    platforms = ["ios"],
)

hello_swift_library(
    name = "HelloWorldLib",
    module_name = "HelloWorldLib",
    srcs = glob(["HelloWorldLib/Sources/*.swift"]),
    deps = [":TodoModels", ":TodoObjCSupport", ":GeneratedDummy", ":ExpandedTemplate"],
    platforms = ["ios"],
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

hello_swift_library(
    name = "GeneratedDummy",
    module_name = "GeneratedDummy",
    srcs = [":GenerateDummySwiftFile"],
    platforms = ["ios"],
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

hello_swift_library(
    name = "ExpandedTemplate",
    module_name = "ExpandedTemplate",
    srcs = [":ExpandTemplateSwiftFile"],
    platforms = ["ios"],
)

## MARK: WatchOS targets

hello_swift_library(
    name = "WatchAppTestsLib",
    module_name = "WatchAppTestsLib",
    testonly = True,
    tags = ["manual"],
    srcs = glob(["WatchApp/WatchAppTests/*.swift"]),
    deps = [":WatchAppLib"],
    platforms = ["watchos"],
)

hello_swift_library(
    name = "WatchAppLib",
    module_name = "WatchAppLib",
    srcs = glob(["WatchApp/WatchAppLib/Sources/*.swift"]),
    deps = [":TodoModels"],
    platforms = ["watchos"],
)

## MARK: MacOS targets

hello_swift_library(
    name = "MacAppTestsLib",
    module_name = "MacAppTestsLib",
    testonly = True,
    srcs = glob(["MacApp/MacAppTests/*.swift"]),
    deps = [":MacAppLib"],
    platforms = ["macos"],
)

hello_swift_library(
    name = "MacAppLib",
    module_name = "MacAppLib",
    srcs = glob(["MacApp/MacAppLib/Sources/*.swift"]),
    deps = [":TodoModels"],
    platforms = ["macos"],
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
    deps = [":HelloWorldLib", ":GeneratedDummy"],
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
