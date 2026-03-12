#!/bin/bash

set -euo pipefail

# Returns 0 (true) if target doesn't exist or differs from source
function needs_update() {
    local source="$1"
    local target="$2"
    ! [ -f "$target" ] || ! cmp -s "$source" "$target"
}

sourcekit_bazel_bsp_path="%sourcekit_bazel_bsp_path%"
bsp_config_path="%bsp_config_path%"
lsp_config_path="%lsp_config_path%"
bazel_wrapper="%bazel_wrapper%"
no_extra_output_base_env="%no_extra_output_base_env%"

bsp_folder_path="$BUILD_WORKSPACE_DIRECTORY/.bsp"
lsp_folder_path="$BUILD_WORKSPACE_DIRECTORY/.sourcekit-lsp"
should_merge_lsp_config="%merge_lsp_config_env%"

mkdir -p "$bsp_folder_path"
mkdir -p "$bsp_folder_path/skbsp_generated"
mkdir -p "$lsp_folder_path"

# Create empty BUILD.bazel file to make skbsp_generated a valid Bazel package
# (skip if one already exists)
if [ ! -f "$bsp_folder_path/skbsp_generated/BUILD.bazel" ] && [ ! -f "$bsp_folder_path/skbsp_generated/BUILD" ]; then
    touch "$bsp_folder_path/skbsp_generated/BUILD.bazel"
fi

# Write the platform deps aspect for library builds
# This aspect ensures consistent action keys between full app builds and individual library builds
cat > "$bsp_folder_path/skbsp_generated/aspect.bzl" << 'ASPECT_EOF'
"""Aspect for collecting platform dependencies with per-target output groups.

This aspect creates individual output groups for each dependency, allowing
you to build a full app but only output specific libraries with correct
platform configuration (iOS, tvOS, watchOS).
"""

ASPECT_OUTPUT_GROUP_PREFIX = "aspect_"

_PROPAGATION_ATTRS = [
    "deps",
    "private_deps",
    "implementation_deps",
    "extension",
    "extensions",
    "frameworks",
    "app_intents",
    "watch_application",
]

def _strip_leading_chars(s, chars):
    for _ in range(len(s)):
        if s and s[0] in chars:
            s = s[1:]
        else:
            break
    return s

def _is_aspect_output_group(group_name):
    clean_name = _strip_leading_chars(group_name, "@_")
    return clean_name.startswith(ASPECT_OUTPUT_GROUP_PREFIX)

PlatformDepsInfo = provider(
    doc = "Provider for collecting platform-specific dependency outputs.",
    fields = {
        "label": "Label of the target",
        "outputs": "Depset of output files from transitive dependencies.",
    },
)

def _sanitize_label(label):
    label_str = str(label)
    label_str = _strip_leading_chars(label_str, "/@")
    sanitized = label_str.replace("/", "_").replace(":", "_").replace("-", "_").replace(".", "_")
    return ASPECT_OUTPUT_GROUP_PREFIX + sanitized

def _collect_dep_outputs(dep, transitive_outputs, transitive_output_groups):
    if PlatformDepsInfo not in dep:
        return
    transitive_outputs.append(dep[PlatformDepsInfo].outputs)
    if OutputGroupInfo in dep:
        for group_name in dir(dep[OutputGroupInfo]):
            if _is_aspect_output_group(group_name):
                output_group = getattr(dep[OutputGroupInfo], group_name, None)
                if type(output_group) == "depset":
                    existing = transitive_output_groups.get(group_name, [])
                    existing.append(output_group)
                    transitive_output_groups[group_name] = existing

def _platform_deps_aspect_impl(target, ctx):
    direct_outputs = []
    if DefaultInfo in target:
        direct_outputs = target[DefaultInfo].files.to_list()

    source_files = []
    if hasattr(ctx.rule.attr, "srcs"):
        for src in ctx.rule.attr.srcs:
            if hasattr(src, "files"):
                source_files.extend(src.files.to_list())

    transitive_outputs = []
    transitive_output_groups = {}

    for attr in _PROPAGATION_ATTRS:
        if hasattr(ctx.rule.attr, attr):
            deps = getattr(ctx.rule.attr, attr)
            if deps == None:
                continue
            deps_list = deps if type(deps) == "list" else [deps]
            for dep in deps_list:
                if dep != None:
                    _collect_dep_outputs(dep, transitive_outputs, transitive_output_groups)

    target_outputs = depset(direct_outputs + source_files, transitive = transitive_outputs)

    output_groups = {
        "platform_deps": target_outputs,
    }

    target_label = ctx.label
    target_group_name = _sanitize_label(target_label)
    output_groups[target_group_name] = target_outputs

    label_str = str(target_label)
    if ":" in label_str:
        package_path = label_str.split(":")[0]
        shorthand_name = _sanitize_label(package_path)
        if shorthand_name != target_group_name:
            output_groups[shorthand_name] = target_outputs

    for group_name, group_depsets in transitive_output_groups.items():
        output_groups[group_name] = depset(transitive = group_depsets)

    return [
        PlatformDepsInfo(
            outputs = target_outputs,
            label = target_label,
        ),
        OutputGroupInfo(**output_groups),
    ]

platform_deps_aspect = aspect(
    implementation = _platform_deps_aspect_impl,
    attr_aspects = _PROPAGATION_ATTRS,
    provides = [PlatformDepsInfo],
)
ASPECT_EOF

# Write the wrapper rule for applying the aspect via rule attribute instead of CLI --aspects.
# This avoids Skyframe cache invalidation from ConfiguredTargetKey instability (bazelbuild/bazel#19914).
cat > "$bsp_folder_path/skbsp_generated/rules.bzl" << 'RULES_EOF'
"""Wrapper rule that applies platform_deps_aspect via rule attribute.

By applying the aspect through a rule attribute (not CLI --aspects),
the ConfiguredTargetKey is stable across builds, preventing potential
Skyframe cache invalidation (bazelbuild/bazel#19914).

No configuration transition is applied — the app target uses its own
internal transitions (from ios_application/tvos_application/etc.) to
configure deps with correct platform settings. This ensures the wrapper
reuses the same ConfiguredTargetValue nodes as a normal app build.
"""

load(":aspect.bzl", "platform_deps_aspect")

def _platform_deps_wrapper_impl(ctx):
    target = ctx.attr.target

    # Forward OutputGroupInfo so --output_groups works on wrapper targets
    output_groups = {}
    if OutputGroupInfo in target:
        for group_name in dir(target[OutputGroupInfo]):
            group = getattr(target[OutputGroupInfo], group_name, None)
            if type(group) == "depset":
                output_groups[group_name] = group

    return [
        DefaultInfo(files = target[DefaultInfo].files),
        OutputGroupInfo(**output_groups),
    ]

_platform_deps_wrapper = rule(
    implementation = _platform_deps_wrapper_impl,
    attrs = {
        "target": attr.label(
            aspects = [platform_deps_aspect],
            mandatory = True,
        ),
    },
    doc = "Wrapper that applies platform_deps_aspect via rule attribute for stable caching.",
)

def platform_deps_wrapper(name, target, testonly = False, visibility = None):
    """Create a wrapper target for an app.

    Args:
        name: Base name for the wrapper target.
        target: The app target label.
        testonly: If True, marks the wrapper as testonly (required for test targets).
        visibility: Visibility for the generated target.
    """
    _platform_deps_wrapper(
        name = name,
        target = target,
        testonly = testonly,
        tags = ["manual"],
        visibility = visibility or ["//visibility:public"],
    )
RULES_EOF

target_bsp_config_path="$bsp_folder_path/skbsp.json"
target_sourcekit_bazel_bsp_path="$bsp_folder_path/sourcekit-bazel-bsp"
target_lsp_config_path="$lsp_folder_path/config.json"

# Update the BSP config if needed
if needs_update "$bsp_config_path" "$target_bsp_config_path"; then
    cp "$bsp_config_path" "$target_bsp_config_path"
    chmod +w "$target_bsp_config_path"
fi

# Update placeholder values in the LSP config if needed
WORKSPACE_ROOT="$BUILD_WORKSPACE_DIRECTORY"
output_base=$(cd "$WORKSPACE_ROOT" && $bazel_wrapper info output_base)
output_path=$(cd "$WORKSPACE_ROOT" && $bazel_wrapper info output_path)
output_path_difference=$(echo "$output_path" | sed "s|$output_base/||")
exec_root=$(cd "$WORKSPACE_ROOT" && $bazel_wrapper info execution_root)
exec_root_difference=$(echo "$exec_root" | sed "s|$output_base/||")
output_path_name=$(echo "$output_path" | sed "s|$exec_root/||")
old_bsp_output_base="${output_base}-sourcekit-bazel-bsp"
if [ "$no_extra_output_base_env" = "1" ]; then
    bsp_output_base="${output_base}"
else
    bsp_output_base="${output_base}/sourcekit-bazel-bsp"
fi
output_path="${bsp_output_base}/${output_path_difference}"
external_root="${bsp_output_base}/${exec_root_difference}/external"

# Clean up the old output base if it exists (from before we nested it in the main one)
if [ -d "$old_bsp_output_base" ]; then
    echo "Cleaning up old output base at $old_bsp_output_base"
    rm -rf "$old_bsp_output_base" > /dev/null 2>&1 &
fi

# Copy to a temp file first since the source may be a symlink in runfiles
lsp_config_tmp=$(mktemp)
cp "$lsp_config_path" "$lsp_config_tmp"
sed -i '' 's|OUTPUT_PATH_PLACEHOLDER|'"$output_path"'|g' "$lsp_config_tmp"
sed -i '' 's|EXTERNAL_ROOT_PLACEHOLDER|'"$external_root"'|g' "$lsp_config_tmp"
sed -i '' 's|OUTPUT_PATH_NAME_PLACEHOLDER|'"$output_path_name"'|g' "$lsp_config_tmp"
sed -i '' 's|WORKSPACE_ROOT_PLACEHOLDER|'"$WORKSPACE_ROOT"'|g' "$lsp_config_tmp"
lsp_config_path="${lsp_config_tmp}"

# Update the LSP config if needed
# For merging, we need to compare the merged result (not the source template)
if [ -f "$target_lsp_config_path" ] && command -v jq &> /dev/null; then
    is_curr_file_valid_json=$(jq -e . "$target_lsp_config_path" > /dev/null 2>&1 && echo "true" || echo "false")
    if [ "$should_merge_lsp_config" = "1" ] && [ "$is_curr_file_valid_json" = "true" ]; then
        jq -S -s '.[0] * .[1]' "$target_lsp_config_path" "$lsp_config_path" > "$target_lsp_config_path.tmp"
    else
        cp "$lsp_config_path" "$target_lsp_config_path.tmp"
    fi
    if ! cmp -s "$target_lsp_config_path.tmp" "$target_lsp_config_path"; then
        mv "$target_lsp_config_path.tmp" "$target_lsp_config_path"
        chmod +w "$target_lsp_config_path"
    else
        rm -f "$target_lsp_config_path.tmp"
    fi
elif needs_update "$lsp_config_path" "$target_lsp_config_path"; then
    cp "$lsp_config_path" "$target_lsp_config_path"
    chmod +w "$target_lsp_config_path"
fi

# Update the BSP binary if needed
# Delete the existing binary first to avoid issues when running this while a server is running.
if needs_update "$sourcekit_bazel_bsp_path" "$target_sourcekit_bazel_bsp_path"; then
    rm -f "$target_sourcekit_bazel_bsp_path" || true
    cp "$sourcekit_bazel_bsp_path" "$target_sourcekit_bazel_bsp_path"
    chmod +w "$target_sourcekit_bazel_bsp_path"
fi

rm -f "$lsp_config_tmp" || true