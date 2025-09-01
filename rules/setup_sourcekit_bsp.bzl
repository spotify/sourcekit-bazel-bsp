def _setup_sourcekit_bsp_impl(ctx):
    rendered_bsp_config = ctx.actions.declare_file("config.json")
    bsp_config_argv = [
        ".bsp/sourcekit-bazel-bsp",
        "serve",
    ]
    for target in ctx.attr.targets:
        bsp_config_argv.append("--target")
        bsp_config_argv.append(target.label)
    bsp_config_argv.append("--bazel-wrapper")
    bsp_config_argv.append(ctx.attr.bazel_wrapper)
    bsp_config_argv.append("--build-test-suffix")
    bsp_config_argv.append(ctx.attr.build_test_suffix)
    bsp_config_argv.append("--separate-aquery-output")
    bsp_config_argv.append(ctx.attr.separate_aquery_output)
    for index_flag in ctx.attr.index_flags:
        bsp_config_argv.append("--index-flag")
        bsp_config_argv.append(index_flag)
    files_to_watch = ','.join(ctx.attr.files_to_watch)
    if files_to_watch:
        bsp_config_argv.append("--files-to-watch")
        bsp_config_argv.append(files_to_watch)
    ctx.actions.expand_template(
        template = ctx.file._bsp_config_template,
        output = rendered_bsp_config,
        substitutions = {
            "%argv%": ", ".join(["\"%s\"" % arg for arg in bsp_config_argv]),
        },
    )
    executable = ctx.actions.declare_file("setup_sourcekit_bsp.sh")
    ctx.actions.expand_template(
        template = ctx.file._setup_sourcekit_bsp_script,
        is_executable = True,
        output = executable,
        substitutions = {
            "%bsp_config_path%": rendered_bsp_config.short_path,
            "%sourcekit_bazel_bsp_path%": ctx.executable._sourcekit_bazel_bsp_tool.short_path,
        },
    )
    tools_runfiles = ctx.runfiles(
        files = [
            ctx.executable._sourcekit_bazel_bsp_tool,
            rendered_bsp_config,
        ],
    )
    return DefaultInfo(
        executable = executable,
        files = depset(direct = [executable]),
        runfiles = tools_runfiles,
    )


setup_sourcekit_bsp = rule(
    implementation = _setup_sourcekit_bsp_impl,
    executable = True,
    doc = "Sets up the sourcekit-bazel-bsp in the current workspace using the provided configuration.",
    attrs = {
        "_bsp_config_template": attr.label(
            doc = "The template for the sourcekit-bazel-bsp configuration.",
            default = "//rules:bsp_config.json.tpl",
            allow_single_file = True,
        ),
        "_setup_sourcekit_bsp_script": attr.label(
            doc = "The script for setting up the sourcekit-bazel-bsp.",
            default = "//rules:setup_sourcekit_bsp.sh.tpl",
            allow_single_file = True,
        ),
        "_sourcekit_bazel_bsp_tool": attr.label(
            doc = "The sourcekit-bazel-bsp binary.",
            default = "//Sources/sourcekit-bazel-bsp",
            cfg = "exec",
            executable = True,
        ),
        "targets": attr.label_list(
            doc = "The *top level* Bazel applications or test targets that this should serve a BSP for. It's best to keep this list small if possible for performance reasons. If not specified, the server will try to discover top-level targets automatically",
            mandatory = True,
        ),
        "bazel_wrapper": attr.string(
            doc = "The name of the Bazel CLI to invoke (e.g. 'bazelisk').",
            default = "bazel",
        ),
        "index_flags": attr.string_list(
            doc = "Flags that should be passed to all indexing-related Bazel invocations. Do not include the -- prefix.",
            default = [],
        ),
        "files_to_watch": attr.string_list(
            doc = "A list of file globs to watch for changes.",
            default = [],
        ),
        "build_test_suffix": attr.string(
            doc = "The expected suffix for build_test targets.",
            default = "_skbsp",
        )
        "separate_aquery_output": attr.bool(
            doc = "Whether to use a separate output base for compiler arguments requests. This greatly increases the performance of the server at the cost of more disk usage.",
            default = False,
        )
    },
)
