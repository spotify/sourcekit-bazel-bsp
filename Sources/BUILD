load("//rules/internal:spm.bzl", "spm_release_binary")

# A Bazel wrapper that run SPM under the hood.
# Ideally we would define everything in Bazel as we used to before this was introduced
# so that users can make good use of caching and other Bazel features,
# but this currently causes duplication on our end. What we can do instead is once this tool advances
# enough so that we can even run tests from the IDE, we can remove the SPM integration entirely
# and move everything to Bazel, essentially allowing us to using this tool to develop the tool itself
# similarly to how Swift eventually started using Swift itself to build its own compiler.
spm_release_binary(
    name = "sourcekit-bazel-bsp",
    package_swift = "//:Package.swift",
    srcs = glob([
        "**/*.swift",
    ]),
    visibility = ["//visibility:public"],
    tags = [
        "no-sandbox",
        "requires-network",
    ],
)
