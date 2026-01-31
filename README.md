# iOS Development (and more) in alternative IDEs like Cursor / VSCode, for Bazel projects

**sourcekit-bazel-bsp** is a [Build Server Protocol](https://build-server-protocol.github.io/) implementation that serves as a bridge between [sourcekit-lsp](https://github.com/swiftlang/sourcekit-lsp) (Swift's official [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)) and your Bazel-based code, giving you the power to break free from the IDE side of Xcode and **develop for Apple platforms like iOS in any IDE that has support for LSPs**, such as Cursor, VSCode, Sublime Text, and even Claude Code itself.

> [!IMPORTANT]
> sourcekit-bazel-bsp is designed specifically for projects that use the [Bazel build system](https://bazel.build/) under the hood. It will not work for regular Xcode projects. For Xcode, check out projects like [xcode-build-server](https://github.com/SolaWing/xcode-build-server) (unrelated to this project and Spotify).

https://github.com/user-attachments/assets/ca5a448d-03b1-4f8e-9de1-e403cc08953c

## Features

- (All IDEs) All of the usual indexing features such as code completion, jump to definition, error annotations, refactoring and more, for Swift, Obj-C, and C++ (via the official [sourcekit-lsp](https://github.com/swiftlang/sourcekit-lsp))
- (Cursor / VSCode): Building, launching, debugging (via [lldb-dap](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.lldb-dap)), testing (both via the _Testing_ tab and via the source file itself), as well as simulator management, all from within the IDE (via our [companion extension](ide/vscode/README.md))

## Requirements

- (To use the tool) Swift 6.1+ toolchain (equivalent to Xcode 16.4+)
  - Note that even though sourcekit-bazel-bsp itself is completely detached from Xcode, **you will still need to have Xcode installed on your machine to do any sort of actual Apple development.** This is because installing Xcode is currently the only way to get access to and manage the platform toolchains, so even though this tool allows you to break free from the Xcode IDE itself, you still need to have it around for toolchain reasons. In order to completely avoid Xcode, we would need Apple to detach it from the toolchains and all their related tooling.
- (To compile the tool from source) Xcode 26

## Initial Setup Instructions

### Shared Instructions for All IDEs

- Add sourcekit-bazel-bsp as a dependency on your `MODULE.bazel` file:

```python
bazel_dep(name = "sourcekit_bazel_bsp", version = "0.6.0", repo_name = "sourcekit_bazel_bsp")
```

- Define a `setup_sourcekit_bsp` rule in a BUILD.bazel file of your choice. [You can find the full list of arguments here](rules/setup_sourcekit_bsp.bzl). Although the exact setup differs from project to project, here's what an example setup would look like:

```python
load("@sourcekit_bazel_bsp//rules:setup_sourcekit_bsp.bzl", "setup_sourcekit_bsp")

setup_sourcekit_bsp(
    name = "setup_sourcekit_bsp_example_project",
    files_to_watch = [
        "HelloWorld/**/*.swift",
        "HelloWorld/**/*.h",
        "HelloWorld/**/*.m",
        "HelloWorld/**/*.mm",
        "HelloWorld/**/*.c",
        "HelloWorld/**/*.hpp",
        "HelloWorld/**/*.cpp"
    ],
    index_flags = [
        "config=index_build",
    ],
    index_build_batch_size = 10,
    targets = [
        "//HelloWorld/...",
    ],
)
```

- Run `bazel run {path to the rule, e.g //:setup_sourcekit_bsp}`.

This will result in the necessary configuration files being added to your repository. Users should then re-run the above command whenever the rule's parameters changes. We recommend adding `.bsp/skbsp_generated` as well as the copied binaries and `.bsp/skbsp.json` to your `.gitignore`.

The next step depends on which IDE you want to use this integration with. Follow the instructions below that match your choice.

### Cursor / VSCode

- Download and install the official [Swift](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode) and [LLDB-DAP](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.lldb-dap) extensions.
  - Note: (Cursor) As of writing, you won't be able to install these extensions directly from Cursor's Marketplace. You will need to download the `.vsix` files separatedly and install them by either dragging them into Cursor or using the Cursor CLI. One way to obtain the `.vsix` files is by finding the extensions in **VSCode** and right clicking them -> `Download VSIX`.
  - For the Swift extension, we recommend disabling the SwiftPM and Swiftly integrations as they can interfere with the BSP, as well as enabling the IDE's native auto-save function for a better experience. It's also a good idea to set up your `files.exclude` setting to cover all Bazel symlinks. For a complete list of recommended settings, check out the setup script from our [Example project](./Example/tools/vscode/setup_sourcekit_vscode_settings.sh). You can see them after running the project generation.
- **(Optional)** Configure your workspace to use a custom `sourcekit-lsp` binary by placing the provided binary from the release archive (or compiling/providing one of your own) at a place of your choice, creating a `.vscode/settings.json` JSON file at the root of your repository, and adding the following entry to it: `"swift.sourcekit-lsp.serverPath": "(absolute path to the sourcekit-lsp binary to use)"`
  - This is not strictly necessary. However, as we currently make use of LSP features that are not yet shipped with Xcode, you may face performance and other usability issues when using the version that is shipped with Xcode. Consider using the version provided alongside sourcekit-bazel-bsp (or compiling/providing your own) for the best experience.
- **(Optional)** To enable features like building and testing from within the IDE, follow the setup instructions for our [companion extension](ide/vscode/README.md). You can skip this if you're only interested in the indexing features such as jump-to-definition.
- On the IDE, open a workspace containing the repository in question. If you already had one open, either restart the language server (`Cmd+Shift+P -> Swift: Restart LSP Server`) or reload the entire window (`Cmd+Shift+P -> Reload Window`) if you don't see the previous option. The BSP will then automatically bootstrap itself, with several progress indicators showing at the bottom of the IDE. It may take a while for the indexing features to kick in the first time you use it due to the lack of cache, but subsequent runs should be much faster.

#### After Integrating

While a *complete* indexing run can take a very long time on large projects, **keep in mind that you don't need one.** As long as the individual target you're working with is indexed (which happens automatically as you start working on it, as the LSP prioritizes targets you're actively modifying), all of the usual indexing features will work as you'd expect. Make sure to also check the best practices below to further optimize the BSP's performance.

If you experience any trouble trying to get it to work, check out the [Example/ folder](./Example) for a test project with a pre-configured Bazel and `.bsp/` folder setup. The _Troubleshooting_ section below also contains instructions on how to make sure the integration is working and debug sourcekit-bazel-bsp.

### Other IDEs, and Claude Code

The setup instructions for other IDEs (and by extension, Claude Code) will depend on how the IDE integrates with LSPs. You should then search for instructions on how to install sourcekit-lsp on your IDE of choice and enable background indexing. We also recommend finding a way to override the sourcekit-lsp binary itself for the same reasons described in the Cursor / VSCode instructions.

Although the main focus of this project is specifically Cursor / VSCode, we are very interested in knowing what your experience was integrating it with other IDEs. If you've found concrete setup steps for a particular IDE, you are welcome to open a PR including it in this README file.

## Best Practices

- When working with large apps, consider being more explicit about the task you're going to do. This means that instead of importing the _entire app at all times_ or running wide-reaching wildcards like `//...`, try to import only a small group of test targets that you think will be required to perform the task. This will greatly increase the performance of the IDE.
    - The BSP's many filtering arguments can be particularly useful for more complex cases.
    - For smaller apps, this doesn't make much difference and it should be fine to import the entire app.

## Bazel Caching Implications

The BSP by default works by attempting to build your library targets individually with a set of platform flags based on the library's parent app, which is an action that currently does not share action cache keys with the compilation of the apps themselves. If your goal is to have index builds share cache with regular app builds, this would mean that as of writing you would end up with two sets of artifacts.

If this is undesirable, you can pass the `--compile-top-level` flag to make the BSP compile the target's **parent** instead, without any special flags. We recommend using this for projects that define fine-grained `*_build_test` targets and providing them as top-level targets for the BSP, as those don't suffer from this issue and thus enables maximum predictability and cacheability.

## Troubleshooting

### (Cursor / VSCode) Making sure the integration is working

The integration will generally display errors on the IDE if something went wrong, but if you see nothing, try the following:

- Check if you have a `Swift` option on on the Output tab of the IDE. This should say something like "Activating Swift for...". After a while, the output will update to state that the extension activated successfully ("Extension activation completed"). You should also see an entry that says `(found 1 packages)` and another one saying `Added package folder (your_workspace_folder).` These indicate that the Swift extension has correctly recognized the workspace as a Swift project.
- At this point, another option called `SourceKit Language Server` will show up, with progress indicators popping up at the bottom of the IDE (e.g. "sourcekit-bazel-bsp: Initializing...") shortly after. This means the integration is working correctly.

After a while, indexing logs will show up on a separate `SourceKit-LSP: Indexing` tab. These are particularly useful for uncovering issues with either your setup or the BSP itself as they display all individual compilations triggered by sourcekit-lsp.

### Seeing sourcekit-bazel-bsp's logs

sourcekit-bazel-bsp uses Apple's OSLog infrastructure under the hood. To see the tool's logs, run `log stream --process sourcekit-bazel-bsp --debug` on a terminal session. (Alternatively, if you're using our Cursor / VSCode companion extension, you can see these logs directly from the special `SourceKit Bazel BSP (Server)` output tab.)

Some logs may be redacted. To enable extended logging and expose those logs, install the configuration profile at [as described here](https://support.apple.com/guide/mac-help/configuration-profiles-standardize-settings-mh35561/mac#mchlp41bd550) You will then able to see the redacted logs.

If you wish for the logs to become redacted again, you can remove the configuration profile [as described here.](https://support.apple.com/guide/mac-help/configuration-profiles-standardize-settings-mh35561/mac#mchlpa04df41.)

### Debugging sourcekit-bazel-bsp itself

Since sourcekit-bazel-bsp is initialized from within sourcekit-lsp, debugging it requires you to start a lldb session in advance. You can do it with the following command: `lldb --attach-name sourcekit-bazel-bsp --wait-for`

Once the lldb session is initialized, triggering the initialization of the Swift extension on your IDE of choice (e.g. opening a Swift file in VSCode) should eventually cause lldb to start a debugging session.
