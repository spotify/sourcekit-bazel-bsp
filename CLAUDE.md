# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

sourcekit-bazel-bsp is a Build Server Protocol (BSP) implementation that bridges sourcekit-lsp (Swift's official Language Server Protocol) with Bazel-based iOS projects. It enables iOS development in alternative IDEs like Cursor and VSCode by providing language server features without requiring Xcode IDE.

The project itself is built using Swift Package Manager. There is also a `Example/` folder containing a Bazel iOS application demonstrating the tool's functionality.

## Common Commands

### For the tool itself
- **Build the project**: `swift build`
- **Debug build**: `swift build`
- **Release build**: `swift build -c release`
- **Run tests**: `swift test`

### For the example project
- **Build the iOS example app**: `bazelisk build //HelloWorld`
- **Test the iOS example app**: `bazelisk test //HelloWorld/HelloWorldTests:HelloWorldTests`

## Architecture Overview

### Core Components

1. **BSP Server** (`BSPServer.swift`)
   - Main server implementation using JSONRPCConnection
   - Handles client lifecycle and message routing

2. **Message Handler** (`BSPServerMessageHandler.swift`)
   - Protocol defining BSP request/notification handling
   - Routes incoming requests to appropriate handlers

3. **Request Handlers** (`Requests/`)
   - `InitializeRequestHandler.swift` - BSP initialization
   - `WorkspaceBuildTargetsHandler.swift` - Target discovery
   - `BuildTargetSourcesHandler.swift` - Source file resolution
   - `TextDocumentSourceKitOptionsHandler.swift` - SourceKit configuration
   - `PrepareTargetHandler.swift` - Build preparation

4. **Command Structure** (`Commands/`)
   - Uses Swift ArgumentParser for CLI interface
   - Main entry point in `SourcekitBazelBsp.swift`

When making changes to the BSP handling code, you should always first inspect how SourceKit-LSP handles will handle the request on their end. The source code for SourceKit-LSP should be available locally inside the `.build` folder after building the tool for the first time.

### Key Dependencies
- **sourcekit-lsp**: Provides BuildServerProtocol and LSPBindings. Receives BSP requests and forwards to this server
- **Bazel, rules_swift, rules_apple, and apple_support**: Common Bazel-related support for Apple projects, for the example project
