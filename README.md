# iOS Development (and more) in alternative IDEs like Cursor / VSCode, for Bazel projects

**sourcekit-bazel-bsp** is a [Build Server Protocol](https://build-server-protocol.github.io/) implementation that serves as a bridge between [sourcekit-lsp](https://github.com/swiftlang/sourcekit-lsp) (Swift's official [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)) and your Bazel-based code, giving you the power to break free from the IDE side of Xcode and **develop for Apple platforms like iOS in any IDE that has support for LSPs**, such as Cursor and VSCode.

> [!IMPORTANT]
> sourcekit-bazel-bsp is designed specifically for projects that use the [Bazel build system](https://bazel.build/) under the hood. It will not work for regular Xcode projects. For Xcode, check out projects like [xcode-build-server](https://github.com/SolaWing/xcode-build-server) (unrelated to this project and Spotify).

> [!WARNING]
> sourcekit-bazel-bsp is currently in very early stages of development and is not ready for production usage. It currently works only at a limited capacity and is missing several important features.

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

- Swift 6.1+ toolchain (equivalent to Xcode 16.4+)
    - Note that even though sourcekit-bazel-bsp itself is completely detached from Xcode, **you will still need to have Xcode installed on your machine to do any sort of actual Apple development.** This is because installing Xcode is currently the only way to get access to and manage the platform toolchains, so even though this tool allows you to break free from the Xcode IDE itself, you still need to have it around for toolchain reasons. In order to completely avoid Xcode, we would need Apple to detach it from the toolchains and all their related tooling.

## Initial Setup Instructions

### Cursor / VSCode

- Make sure your Bazel project is configured to generate Swift/Obj-C indexing data and debug symbols, either by default or under a specific config.
    - Detailed information on this is currently WIP, but you can check out the example project for an example.
- Download and install [the official Swift extension](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode) for Cursor / VSCode.
- Copy the .bsp/ folder on this repository to the root of the repository you'd like to use this tool for.
- Edit the `argv` fields in `.bsp/apple.json` to match the details for your app / setup.
- On Cursor / VSCode, open a workspace containing the repository in question.
- On the settings page for the Swift extension, enable `SourceKit-LSP: Background Indexing` at the **workspace level**. It **has** to be workspace settings; this specific setting is not supported at the folder level.
- Reload your workspace (`Cmd+Shift+P -> Reload Window`)

After following these steps, the `SourceKit Language Server` output tab (*Cmd+Shift+U*) should show up when opening Swift files, and indexing-related actions will start popping up at the bottom of the IDE after a while alongside a new `SourceKit-LSP: Indexing` output tab.

### Other IDEs

The setup instructions depend on how the IDE integrates with LSPs. You should then search for instructions on how to install sourcekit-lsp on your IDE of choice and enable background indexing. After that, follow the `.bsp/` related steps from the above instructions. Keep in mind that this since project is developed specifically with Cursor / VSCode in mind, we cannot say how well sourcekit-bazel-bsp would work with other IDEs.

## Example Project

This repo contains an example project with a pre-prepared Bazel and `.bsp` configuration. Check it out if you want to see this project working on a controlled environment. Make sure to first read the README on that folder to make sure its configured correctly before trying it out.
