"""
Bazel rule for injecting BSP settings into the user's VSCode settings file,
to be used in conjunction with sourcekit-bazel-bsp as described by its README.
https://github.com/spotify/sourcekit-bazel-bsp
"""

def _setup_vscode_settings_for_bsp_impl(ctx):
    executable = ctx.actions.declare_file("setup_sourcekit_vscode_settings.sh")

    launchable_targets_formatted = " ".join(ctx.attr.launchable_targets) if ctx.attr.launchable_targets else ""
    launch_args_formatted = " ".join(ctx.attr.launch_args) if ctx.attr.launch_args else ""
    extra_build_flags_formatted = " ".join(ctx.attr.extra_build_flags) if ctx.attr.extra_build_flags else ""
    test_build_flags_formatted = " ".join(ctx.attr.test_build_flags) if ctx.attr.test_build_flags else ""
    test_args_formatted = " ".join(ctx.attr.test_args) if ctx.attr.test_args else ""

    ctx.actions.expand_template(
        template = ctx.file._setup_sourcekit_vscode_settings_script,
        is_executable = True,
        output = executable,
        substitutions = {
            "%extra_build_flags%": extra_build_flags_formatted,
            "%launch_args%": launch_args_formatted,
            "%launchable_targets%": launchable_targets_formatted,
            "%sourcekit_lsp_path%": ctx.executable.sourcekit_lsp.short_path if ctx.executable.sourcekit_lsp else "",
            "%test_args%": test_args_formatted,
            "%test_build_flags%": test_build_flags_formatted,
        },
    )
    if ctx.executable.sourcekit_lsp:
        tools_runfiles = ctx.runfiles(
            files = [
                ctx.executable.sourcekit_lsp,
            ],
        )
    else:
        tools_runfiles = None
    return DefaultInfo(
        executable = executable,
        files = depset(direct = [executable]),
        runfiles = tools_runfiles,
    )

setup_vscode_settings_for_bsp = rule(
    implementation = _setup_vscode_settings_for_bsp_impl,
    executable = True,
    doc = "Configures VSCode / Cursor's settings for usage with sourcekit-bazel-bsp.",
    attrs = {
        "extra_build_flags": attr.string_list(
            doc = "Additional flags to pass to the bazelisk build command when building targets.",
            default = [],
            mandatory = False,
        ),
        "launch_args": attr.string_list(
            doc = "Additional arguments to pass to the bazelisk run command when launching apps.",
            default = [],
            mandatory = False,
        ),
        "launchable_targets": attr.string_list(
            doc = "The labels of the launchable targets to be included in the launch.json file.",
            default = [],
            mandatory = False,
        ),
        "sourcekit_lsp": attr.label(
            doc = "The path to the sourcekit-lsp binary.",
            allow_single_file = True,
            cfg = "exec",
            executable = True,
            mandatory = False,
        ),
        "test_args": attr.string_list(
            doc = "Additional arguments to pass to the test runner.",
            default = [],
            mandatory = False,
        ),
        "test_build_flags": attr.string_list(
            doc = "Additional flags to pass to the bazelisk test command when running tests.",
            default = [],
            mandatory = False,
        ),
        "_setup_sourcekit_vscode_settings_script": attr.label(
            doc = "The script for setting up sourcekit-lsp with VSCode / Cursor.",
            default = Label("//tools/vscode:setup_sourcekit_vscode_settings.sh.tpl"),
            allow_single_file = True,
        ),
    },
)
