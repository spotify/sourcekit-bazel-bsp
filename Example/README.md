# Example (Claude/Cursor/VSCode)

This is a simple collection of iOS/watchOS/macOS apps that lets you see sourcekit-bazel-bsp in action. It covers not only the indexing setup, but also correctly sets up your IDE settings with a list of recommended configs that includes the ones necessary by the companion extension.

This example and instructions were designed specifically for **Cursor**, but should also work for VSCode. You can also use this to test the **Claude Code** integration.

## Initial Setup Instructions

- Make sure you fulfill the toolchain requirements for sourcekit-bazel-bsp, available at the main README.
- Install [bazelisk](https://github.com/bazelbuild/bazelisk) if you haven't already: `brew install bazelisk`
- Make sure you're using **Xcode 26.1.1** as this is what this project was developed for.
- (Optional) To enable features like building and testing directly from within the IDE, [install our companion extension.](../ide/vscode/README.md)
- On this folder, run: `bazelisk run //HelloWorld:vscode`

### If testing the Claude Code integration

- Uninstall the official swift-lsp plugin if you installed it previously.

Launching Claude on this folder should enable it to launch sourcekit-lsp + sourcekit-bazel-bsp when prompted about Swift files. To test the integration, ask it about its Swift LSP capabilities.

### If testing the Cursor/VSCode integration

- Open a workspace targeting this folder, or reload it if you already had one.
- The integration should then start working immediately. Read the `After Integrating` section of the main README for more info on how to make sure the integration worked, if you haven't already.

#### Building, Testing, and Launching / Debugging

If you have followed the steps to install our companion extension, you'll be able to perform a wide variety of IDE-related tasks via the extension's dedicated tab when the project's dependency graph is computed for the time first. For more information on what's supported and how to access these features, check out the [documentation for the extension.](../ide/vscode/README.md)