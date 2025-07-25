load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application", "ios_unit_test", "ios_build_test")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_interop_hint")
load("@aspect_bazel_lib//lib:expand_template.bzl", "expand_template_rule")


swift_library(
    name = "HelloWorldTestsLib",
    module_name = "HelloWorldTestsLib",
    testonly = True,
    tags = ["manual"],
    srcs = glob(["HelloWorldTests/*.swift"]),
    deps = [":HelloWorldLib"],
)

ios_build_test(
    name = "HelloWorldTestsLib_skbsp_ios",
    minimum_os_version = "17.0",
    targets = [
        ":HelloWorldTestsLib",
    ],
)

swift_library(
    name = "TodoModels",
    module_name = "TodoModels",
    srcs = glob(["TodoModels/Sources/*.swift"]),
)

ios_build_test(
    name = "TodoModels_skbsp_ios",
    minimum_os_version = "17.0",
    targets = [
        ":TodoModels",
    ],
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
            "TodoObjCSupport/Sources/*.h",
            "TodoObjCSupport/Sources/*.m",
        ],
    ),
    hdrs = glob(["TodoObjCSupport/Sources/*.h"]),
    aspect_hints = [":TodoObjCSupport_hint"],
)

ios_build_test(
    name = "TodoObjCSupport_skbsp_ios",
    minimum_os_version = "17.0",
    targets = [
        ":TodoObjCSupport",
    ],
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

ios_build_test(
    name = "GeneratedDummy_skbsp_ios",
    minimum_os_version = "17.0",
    targets = [
        ":GeneratedDummy",
    ],
)

swift_library(
    name = "HelloWorldLib",
    module_name = "HelloWorldLib",
    srcs = glob(["HelloWorldLib/Sources/*.swift"]),
    deps = [":TodoModels", ":TodoObjCSupport", ":GeneratedDummy", ":ExpandedTemplate"],
)

ios_build_test(
    name = "HelloWorldLib_skbsp_ios",
    minimum_os_version = "17.0",
    targets = [
        ":HelloWorldLib",
    ],
)

genrule(
    name = "CreateTestCoverageManifest",
    srcs = ["Sources/BazelApp.swift"],
    outs = [
        "CoverageManifest.instrumented_files",
    ],
    cmd = "echo $(SRCS) > $@",
)

ios_unit_test(
    name = "HelloWorldTests",
    minimum_os_version = "17.0",
    test_coverage_manifest = "CoverageManifest.instrumented_files",
    deps = [":HelloWorldTestsLib"],
)

ios_application(
    name = "HelloWorld",
    bundle_id = "com.example.HelloWorld",
    families = ["iphone", "ipad"],
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "17.0",
    deps = [":HelloWorldLib", ":GeneratedDummy"],
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

ios_build_test(
    name = "ExpandedTemplate_skbsp_ios",
    minimum_os_version = "17.0",
    targets = [
        ":ExpandedTemplate",
    ],
)

