#!/bin/bash

set -e

# Bash script that handles the installation of .sourcekit-lsp/config.json and VSCode's tasks.json and launch.json files.

function bail() {
  echo -e "\033[0;31merror: $*\033[0m"
  exit 1
}

function is_valid_json() {
  jq -e . "$1" > /dev/null || bail "$1 is not a valid JSON file!"
}

if ! command -v jq &> /dev/null; then
  bail "You need \`jq\` to run this script. Run 'brew install jq' to install it."
fi

JQ_VERSION=$(jq --version)
# Remove the jq- prefix if it exists
if [[ "$JQ_VERSION" == jq-* ]]; then
  JQ_VERSION=${JQ_VERSION#jq-}
fi
EXPECTED_JQ_VERSION="1.8.1"
if ! { echo "$EXPECTED_JQ_VERSION"; echo "$JQ_VERSION"; } | sort --version-sort --check 2>/dev/null; then
  bail "Your local \`jq\` is too old (${JQ_VERSION}). You need version ${EXPECTED_JQ_VERSION} or higher to run this script. You can install it with brew: 'brew install jq'."
fi

sourcekit_lsp_path="%sourcekit_lsp_path%"
launchable_targets="%launchable_targets%"
extra_build_flags="%extra_build_flags%"
test_build_flags="%test_build_flags%"
test_args="%test_args%"
launch_args="%launch_args%"
settings_folder_path="$BUILD_WORKSPACE_DIRECTORY/.vscode"
bsp_folder_path="$BUILD_WORKSPACE_DIRECTORY/.bsp"

mkdir -p "$settings_folder_path" || true
mkdir -p "$bsp_folder_path" || true

target_settings_path="$settings_folder_path/settings.json"
target_sourcekit_lsp_path="$bsp_folder_path/sourcekit-lsp"

if [ ! -f "$target_settings_path" ]; then
    echo "{}" > "$target_settings_path"
fi

# Delete the existing binary first to avoid issues when running this while a server is running.
rm -f "$target_sourcekit_lsp_path" || true
if [ -n "$sourcekit_lsp_path" ]; then
    cp "$sourcekit_lsp_path" "$target_sourcekit_lsp_path"
fi

chmod +w "$target_settings_path"
if [ -n "$sourcekit_lsp_path" ]; then
    chmod +w "$target_sourcekit_lsp_path"
fi

# First, validate the file is an actual json (and not an empty file)
is_valid_json "$target_settings_path"

# Then, add the sourcekit-lsp setting to the file
# Not sure why jq doesn't update the file inline, I couldn't get it to work for some reason. So writing to a tmp path instead.
tmp_json_path="$target_settings_path.tmp"
rm -f "$tmp_json_path" || true
jq -e --arg extra_build_flags "$extra_build_flags" --arg test_build_flags "$test_build_flags" --arg test_args "$test_args" --arg launch_args "$launch_args" --arg launchable_targets "$launchable_targets" '
  . += {
    "debug.hideSlowPreLaunchWarning": true,
    "swift.sourcekit-lsp.trace.server": "messages",
    "swift.disableSwiftPackageManagerIntegration": true,
    "swift.autoGenerateLaunchConfigurations": false,
    "swift.disableAutoResolve": true,
    "swift.sourcekit-lsp.backgroundIndexing": "on",
    "swift.sourcekit-lsp.trace.server": "messages",
    "swift.debugger.debugAdapter": "lldb-dap",
    "swift.outputChannelLogLevel": "debug",
    "swift.disableSwiftlyInstallPrompt": true,
    "sourcekit-bazel-bsp.extraBuildFlags": $extra_build_flags,
    "sourcekit-bazel-bsp.extraTestBuildFlags": $test_build_flags,
    "sourcekit-bazel-bsp.testArgs": $test_args,
    "sourcekit-bazel-bsp.launchArgs": $launch_args,
    "sourcekit-bazel-bsp.appsToAlwaysInclude": $launchable_targets | split(" ") | map(.),
    "search.exclude": {
      "**/.git": true,
      "**/external": true,
      "**/node_modules": true,
      "**/bazel-bin": true,
      "**/bazel-Example": true,
      "**/bazel-out": true,
      "**/bazel-testlogs": true,
      "**/*.xcodeproj": true
    },
    "files.associations": {
        "*.h": "objective-c"
    },
    "files.autoSaveDelay": 500,
    "files.exclude": {
      "**/.git": true,
      "**/external": true,
      "**/node_modules": true,
      "**/bazel-bin": true,
      "**/bazel-Example": true,
      "**/bazel-out": true,
      "**/bazel-testlogs": true,
      "**/*.xcodeproj": true
    },
    "[c]": {
        "files.autoSave": "afterDelay",
    },
    "[cpp]": {
        "files.autoSave": "afterDelay",
    },
    "[objective-c]": {
        "files.autoSave": "afterDelay",
    },
    "[objective-cpp]": {
        "files.autoSave": "afterDelay",
    },
    "[swift]": {
        "files.autoSave": "afterDelay",
    },
  }
' "$target_settings_path" > "$tmp_json_path"
mv "$tmp_json_path" "$target_settings_path"
rm -f "$tmp_json_path" || true
if [ -n "$target_sourcekit_lsp_path" ]; then
  jq -e --arg sklsp "$target_sourcekit_lsp_path" '
  . += {
    "swift.sourcekit-lsp.serverPath": $sklsp
    }
' "$target_settings_path" > "$tmp_json_path"
  mv "$tmp_json_path" "$target_settings_path"
fi
