# AGENTS.md

## Project Overview

sourcekit-bazel-bsp is a Build Server Protocol (BSP) implementation that bridges sourcekit-lsp (Swift's official Language Server Protocol) with Bazel-based iOS projects. It enables iOS development in alternative IDEs like Cursor and VSCode by providing language server features without requiring the Xcode IDE.

The project itself is built using Swift Package Manager. There is also a `Example/` folder containing a Bazel iOS application demonstrating the tool's functionality, as well as a `vscode-extension/` containing a helper VSCode/Cursor extension that acts as a companion to the main BSP code.

## Common Commands

### Base instructions
- When done with your changes, always run the linting, formatting, and test commands mentioned below.
- For Bazel content, always use with `bazelisk` instead of `bazel`.

### For the tool itself
- **Debug build**: `swift build`
- **Release build**: `swift build -c release`
- **Lint**: `swift format lint Sources/ Tests/ Example/ --recursive`
- **Format**: `swift format Sources/ Tests/ Example/ --recursive --in-place`
- **Run tests**: `swift test`
