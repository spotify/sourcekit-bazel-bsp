# iOS Development (and more) in alternative IDEs like Cursor / VSCode, for Bazel projects

**sourcekit-bazel-bsp** is a [Build Server Protocol](https://build-server-protocol.github.io/) implementation that serves as a bridge between [sourcekit-lsp](https://github.com/swiftlang/sourcekit-lsp) (Swift's official [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)) and your Bazel-based code, giving you the power to break free from the IDE side of Xcode and **develop for Apple platforms like iOS in any IDE that has support for LSPs**, such as Cursor and VSCode.

> [!IMPORTANT]
> sourcekit-bazel-bsp is designed specifically for projects that use the [Bazel build system](https://bazel.build/) under the hood. It will not work for regular Xcode projects. For Xcode, check out projects like [xcode-build-server](https://github.com/SolaWing/xcode-build-server) (unrelated to this project and Spotify).

<img width="1462" alt="Cursor running iOS" src="./Example/img/readme.png">

## Features

- [x] All of the usual indexing features such as code completion, jump to definition, error annotations and so on, for both Swift and Obj-C (via the official [sourcekit-lsp](https://github.com/swiftlang/sourcekit-lsp))
- [x] (Cursor / VSCode): Building and launching, all from within the IDE and directly via Bazel (no project generation required!)
- [x] (Cursor / VSCode): Full `lldb` integration, allowing debugging from within the IDE just like Xcode (via [lldb-dap](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.lldb-dap), automatically provided by the official Swift extension)
- [ ] (Cursor / VSCode): Simulator selection from within the IDE
- [ ] (Cursor / VSCode): Automatic generation of build, launch, and debug tasks
- [ ] (Cursor / VSCode): Test explorer & ability to run tests from within the IDE by clicking the tests individually, similarly to Xcode
- [ ] Automatic index and build graph updates when adding / deleting files and targets (in other words, allowing the user to make heavy changes to the project without needing to restart the IDE)

## Requirements

- (To use the tool) Swift 6.1+ toolchain (equivalent to Xcode 16.4+)
  - Note that even though sourcekit-bazel-bsp itself is completely detached from Xcode, **you will still need to have Xcode installed on your machine to do any sort of actual Apple development.** This is because installing Xcode is currently the only way to get access to and manage the platform toolchains, so even though this tool allows you to break free from the Xcode IDE itself, you still need to have it around for toolchain reasons. In order to completely avoid Xcode, we would need Apple to detach it from the toolchains and all their related tooling.
- (To compile the tool from source) Xcode 26

## Initial Setup Instructions

### Cursor / VSCode

- Download and install the official [Swift](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode) and [LLDB-DAP](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.lldb-dap) extensions.
  - Note: (Cursor) As of writing, you won't be able to install these extensions directly from Cursor's Marketplace. You will need to download the `.vsix` files by finding them in VSCode and right clicking the extension -> `Download VSIX`. You can then install the extensions by installing the Cursor CLI and running `cursor --install-extension (vsix_path)`.
- **(Optional)** Configure your workspace to use a custom `sourcekit-lsp` binary by placing the provided binary from the release archive (or compiling/providing one of your own) at a place of your choice, creating a `.vscode/settings.json` JSON file at the root of your repository, and adding the following entry to it: `"swift.sourcekit-lsp.serverPath": "(absolute path to the sourcekit-lsp binary to use)"`
  - This is not strictly necessary. However, as we currently make use of LSP features that are not yet shipped with Xcode, you may face performance and other usability issues when using the version that is shipped with Xcode. Consider using the version provided alongside sourcekit-bazel-bsp (or compiling/providing your own) for the best experience.

The next step is to integrate sourcekit-bazel-bsp with your project:

- Add sourcekit-bazel-bsp as a dependency on your `MODULE.bazel` file:

```python
bazel_dep(name = "sourcekit_bazel_bsp", version = "0.4.0", repo_name = "sourcekit_bazel_bsp")
```

- Define a `setup_sourcekit_bsp` rule in a BUILD.bazel file of your choice and [configure it](rules/setup_sourcekit_bsp.bzl#L77) for your desired setup:

```python
load("@sourcekit_bazel_bsp//rules:setup_sourcekit_bsp.bzl")

setup_sourcekit_bsp(
  name = "setup_sourcekit_bsp",
  ...
)
```

- Run `bazel run {path to the rule, e.g //:setup_sourcekit_bsp}`.

This will result in the necessary configuration files being added to your repository. Users should then re-run the above command whenever the rule's parameters changes.

#### After Integrating

- On the IDE, open a workspace containing the repository in question. If you already had one open, either restart the language server (`Cmd+Shift+P -> Swift: Restart LSP Server`) or reload the entire window (`Cmd+Shift+P -> Reload Window`) if you don't see the previous option.

After following these steps and opening a Swift file, the `SourceKit Language Server` output tab (_Cmd+Shift+U_) should eventually show up (this will take a couple of seconds if the Swift extension needs to be launched on that window), and indexing-related actions will start popping up at the bottom of the IDE after a while alongside a new `SourceKit-LSP: Indexing` output tab when working with those files.

While a complete indexing run can take a very long time on large projects, keep in mind that you don't need one. As long as the individual target you're working with is indexed (which happens automatically as you start working on it, as the LSP prioritizes targets you're actively modifying), all of the usual indexing features will work as you'd expect.

If you experience any trouble trying to get it to work, check out the [Example/ folder](./Example) for a test project with a pre-configured Bazel and `.bsp/` folder setup. The _Troubleshooting_ section below also contains instructions on how to debug sourcekit-bazel-bsp.

### Other IDEs

The setup instructions depend on how the IDE integrates with LSPs. You should then search for instructions on how to install sourcekit-lsp on your IDE of choice and enable background indexing. After that, follow the `.bsp/` related steps from the above instructions. Keep in mind that this since project is developed specifically with Cursor / VSCode in mind, we cannot say how well sourcekit-bazel-bsp would work with other IDEs.

## Bazel Caching Implications

The BSP by default works by attempting to build your library targets individually with a set of platform flags based on the library's parent app, which is an action that currently does not share action cache keys with the compilation of the apps themselves. If your goal is to have index builds share cache with regular app builds, this would mean that as of writing you would end up with two sets of artifacts.

If this is undesirable, you can pass the `--compile-top-level` flag to make the BSP compile the target's **parent** instead, without any special flags. We recommend using this for projects that define fine-grained `*_build_test` targets and providing them as top-level targets for the BSP, as those don't suffer from this issue and thus enables maximum predictability and cacheability.

## Troubleshooting

### Seeing sourcekit-bazel-bsp's logs

sourcekit-bazel-bsp uses Apple's OSLog infrastructure under the hood. To see the tool's logs, run `log stream --process sourcekit-bazel-bsp --debug` on a terminal session.

Some logs may be redacted. To enable extended logging and expose those logs, install the configuration profile at [as described here](https://support.apple.com/guide/mac-help/configuration-profiles-standardize-settings-mh35561/mac#mchlp41bd550) You will then able to see the redacted logs.

If you wish for the logs to become redacted again, you can remove the configuration profile [as described here.](https://support.apple.com/guide/mac-help/configuration-profiles-standardize-settings-mh35561/mac#mchlpa04df41.)

### Debugging

Since sourcekit-bazel-bsp is initialized from within sourcekit-lsp, debugging it requires you to start a lldb session in advance. You can do it with the following command: `lldb --attach-name sourcekit-bazel-bsp --wait-for`

Once the lldb session is initialized, triggering the initialization of the Swift extension on your IDE of choice (e.g. opening a Swift file in VSCode) should eventually cause lldb to start a debugging session.
