load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application", "ios_unit_test", "ios_build_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_interop_hint")
load("@aspect_bazel_lib//lib:expand_template.bzl", "expand_template_rule")
load("//tools:apple.bzl", "hello_objc_library", "hello_swift_library", "IOS_MINIMUM_OS_VERSION")

## MARK: Libraries

hello_swift_library(
    name = "HelloWorldTestsLib",
    module_name = "HelloWorldTestsLib",
    testonly = True,
    tags = ["manual"],
    srcs = glob(["HelloWorldTests/*.swift"]),
    deps = [":HelloWorldLib"],
)

hello_swift_library(
    name = "TodoModels",
    module_name = "TodoModels",
    srcs = glob(["TodoModels/Sources/*.swift"]),
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
)

hello_swift_library(
    name = "HelloWorldLib",
    module_name = "HelloWorldLib",
    srcs = glob(["HelloWorldLib/Sources/*.swift"]),
    deps = [":TodoModels", ":TodoObjCSupport", ":GeneratedDummy", ":ExpandedTemplate"],
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
