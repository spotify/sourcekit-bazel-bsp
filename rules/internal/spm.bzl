BASE_SCRIPT = """#!/bin/bash
set -e
ORIG_PATH=$(pwd)
PKG_PATH="{}"
PKG_DIR=$(dirname $PKG_PATH)

cd $PKG_DIR
swift build -c release
BIN_PATH=$(realpath .build/release/{})
cd $ORIG_PATH
cp $BIN_PATH "{}"
"""

def _spm_release_binary_impl(ctx):
    binary_name = ctx.attr.name
    binary_output = ctx.actions.declare_file(binary_name)

    build_script = ctx.actions.declare_file("build_spm.sh")
    base_script = BASE_SCRIPT.format(
        ctx.file.package_swift.path,
        ctx.attr.name,
        binary_output.path,
    )
    ctx.actions.write(
        output = build_script,
        content = base_script,
        is_executable = True,
    )

    ctx.actions.run(
        inputs = ctx.files.srcs + ctx.files.package_swift,
        outputs = [binary_output],
        executable = build_script,
        arguments = [],
        mnemonic = "SPMBuild",
        progress_message = "Building SPM binary: {}".format(ctx.attr.name),
        use_default_shell_env = True,
        execution_requirements = {
            "no-sandbox": "1",
            "requires-network": "1",
        },
    )

    return DefaultInfo(
        executable = binary_output,
        files = depset([binary_output]),
    )

spm_release_binary = rule(
    implementation = _spm_release_binary_impl,
    executable = True,
    doc = "Builds a Swift package using SPM with 'swift build -c release' and returns the compiled binary.",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".swift"],
            mandatory = True,
        ),
        "package_swift": attr.label(
            doc = "The Package.swift file at the workspace root.",
            allow_single_file = True,
            mandatory = True,
        ),
    },
)
