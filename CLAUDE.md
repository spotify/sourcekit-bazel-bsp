# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

sourcekit-bazel-bsp is a Build Server Protocol (BSP) implementation that bridges sourcekit-lsp (Swift's official Language Server Protocol) with Bazel-based iOS projects. It enables iOS development in alternative IDEs like Cursor and VSCode by providing language server features without requiring the Xcode IDE.

The project itself is built using Swift Package Manager. There is also a `Example/` folder containing a Bazel iOS application demonstrating the tool's functionality.

## Common Commands

### For the tool itself
- **Build the project**: `swift build`
- **Debug build**: `swift build`
- **Release build**: `swift build -c release`
- **Lint**: `swift format lint Sources/ Tests/ Example/ --recursive`
- **Format**: `swift format Sources/ Tests/ Example/ --recursive --in-place`
- **Run tests**: `swift test`

### For the example project
- **Build the iOS example app**: `bazelisk build //HelloWorld`
- **Test the iOS example app**: `bazelisk test //HelloWorld/HelloWorldTests:HelloWorldTests`

## Architecture Overview

### Core Components

1. **BSP Server** (`Sources/SourceKitBazelBSP/Server/SourceKitBazelBSPServer.swift`)
   - Main server implementation using LSPConnection
   - Handles client lifecycle and message routing + registration
   - Server configuration managed by `BaseServerConfig.swift` and `InitializedServerConfig.swift`

2. **Message Handlers** (`Sources/SourceKitBazelBSP/Server/MessageHandler/`)
   - `BSPMessageHandler.swift` - Main (dynamic, registration-based) message dispatcher

3. **Request Handlers** (`Sources/SourceKitBazelBSP/RequestHandlers/`)
   - Various handlers that are dynamically registered to the main BSPMessageHandler by the server.

4. **Entry Point** (`Sources/sourcekit-bazel-bsp/`)
   - CLI-related code and argument parsing.

5. **Proto Bindings** (`Sources/BazelProtobufBindings/`)
   - Protobuf bindings to allow type-safe querying with Bazel.

When making changes to the message handlers, you should always first inspect how SourceKit-LSP handles will handle the request on their end. The source code for SourceKit-LSP should be available locally inside the `.build/checkouts/sourcekit-lsp` folder after building the tool for the first time.

### Key Dependencies
- **sourcekit-lsp**: Provides BuildServerProtocol and LSPBindings. Receives BSP requests and forwards to this server
- **Bazel, rules_swift, rules_apple, and apple_support**: Common Bazel-related support for Apple projects, for the example project
- **swift-protobuf**: For generating the Bazel bindings.
