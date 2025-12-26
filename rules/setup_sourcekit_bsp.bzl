def _setup_sourcekit_bsp_impl(ctx):
    # Config of the BSP itself, a.k.a .bsp/skbsp.json
    rendered_bsp_config = ctx.actions.declare_file("skbsp.json")
    # Configs for sourcekit-lsp, a.k.a .sourcekit-lsp/config.json
    rendered_lsp_config = ctx.actions.declare_file("config.json")

    # BSP setup bits
    bsp_config_argv = [
        ".bsp/sourcekit-bazel-bsp",
        "serve",
    ]
    for target in ctx.attr.targets:
        bsp_config_argv.append("--target")
        bsp_config_argv.append(target)
    bsp_config_argv.append("--bazel-wrapper")
    bsp_config_argv.append(ctx.attr.bazel_wrapper)
    if ctx.attr.compile_top_level:
        bsp_config_argv.append("--compile-top-level")
    for index_flag in ctx.attr.index_flags:
        bsp_config_argv.append("--index-flag")
        bsp_config_argv.append(index_flag)
    for top_level_rule in ctx.attr.top_level_rules_to_discover:
        bsp_config_argv.append("--top-level-rule-to-discover")
        bsp_config_argv.append(top_level_rule)
    for dependency_rule in ctx.attr.dependency_rules_to_discover:
        bsp_config_argv.append("--dependency-rule-to-discover")
        bsp_config_argv.append(dependency_rule)
    for target in ctx.attr.top_level_targets_to_exclude:
        bsp_config_argv.append("--top-level-target-to-exclude")
        bsp_config_argv.append(target)
    for target in ctx.attr.dependency_targets_to_exclude:
        bsp_config_argv.append("--dependency-target-to-exclude")
        bsp_config_argv.append(target)
    files_to_watch = ",".join(ctx.attr.files_to_watch)
    if files_to_watch:
        bsp_config_argv.append("--files-to-watch")
        bsp_config_argv.append(files_to_watch)
    ctx.actions.expand_template(
        template = ctx.file._bsp_config_template,
        output = rendered_bsp_config,
        substitutions = {
            "%argv%": ",\n        ".join(["\"%s\"" % arg for arg in bsp_config_argv]),
        },
    )

    # sourcekit-lsp setup bits
    lsp_config_json = {
        "backgroundIndexing": True,
        "backgroundPreparationMode": "build",
        "defaultWorkspaceType": "buildServer",
        "buildServerWorkspaceRequestsTimeout": 999, # Temporary while we don't follow the recommendation of returning from buildTargets as fast as possible + use notifications
        "buildSettingsTimeout": 999, # Temporary while we don't follow the recommendation of returning from buildTargets as fast as possible + use notifications
    }
    if ctx.attr.index_build_batch_size:
        lsp_config_json["preparationBatchingStrategy"] = {
            "strategy": "fixedTargetBatchSize",
            "batchSize": ctx.attr.index_build_batch_size
        }
    ctx.actions.write(rendered_lsp_config, json.encode_indent(lsp_config_json, indent = "  "))

    # Generating the script that ties everything together
    executable = ctx.actions.declare_file("setup_sourcekit_bsp.sh")
    ctx.actions.expand_template(
        template = ctx.file._setup_sourcekit_bsp_script,
        is_executable = True,
        output = executable,
        substitutions = {
            "%bsp_config_path%": rendered_bsp_config.short_path,
            "%lsp_config_path%": rendered_lsp_config.short_path,
            "%sourcekit_bazel_bsp_path%": ctx.executable.sourcekit_bazel_bsp.short_path,
        },
    )
    tools_runfiles = ctx.runfiles(
        files = [
            ctx.executable.sourcekit_bazel_bsp,
            rendered_bsp_config,
            rendered_lsp_config,
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
    doc = "Configures sourcekit-bazel-bsp in the current workspace using the provided configuration.",
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
        "sourcekit_bazel_bsp": attr.label(
            doc = "The path to the sourcekit-bazel-bsp binary. Will compile from source if not provided.",
            default = "//Sources:sourcekit-bazel-bsp",
            allow_single_file = True,
            cfg = "exec",
            executable = True,
        ),
        # We avoid using label_list here to not trigger unnecessary bazel dependency graph checks.
        "targets": attr.string_list(
            doc = "The *top level* Bazel applications or test targets that this should serve a BSP for. Wildcards are supported (e.g. //foo/...). It's best to keep this list small if possible for performance reasons. If not specified, the server will try to discover top-level targets automatically",
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
        "top_level_rules_to_discover": attr.string_list(
            doc = "A list of top-level rule types to discover targets for (e.g. 'ios_application', 'ios_unit_test'). If not specified, all supported top-level rule types will be used for target discovery.",
            default = [],
        ),
        "dependency_rules_to_discover": attr.string_list(
            doc = "A list of dependency rule types to discover targets for (e.g. 'swift_library', 'objc_library', 'cc_library'). If not specified, all supported dependency rule types will be used for target discovery.",
            default = [],
        ),
        "top_level_targets_to_exclude": attr.string_list(
            doc = "A list of target patterns to exclude from top-level targets in the cquery. Wildcards are supported (e.g. //foo/...).",
            default = [],
        ),
        "dependency_targets_to_exclude": attr.string_list(
            doc = "A list of target patterns to exclude from dependency targets in the cquery. Wildcards are supported (e.g. //foo/...).",
            default = [],
        ),
        "index_build_batch_size": attr.int(
            doc = "The number of targets to prepare in parallel. If not provided, will default to 1.",
            mandatory = False,
        ),
        "compile_top_level": attr.bool(
            doc = "Instead of attempting to build targets individually, build the top-level parent. If your project contains build_test targets for your individual libraries and you're passing them as the top-level targets for the BSP, you can use this flag to build those targets directly for better predictability and caching.",
            default = False,
        ),
    },
)
