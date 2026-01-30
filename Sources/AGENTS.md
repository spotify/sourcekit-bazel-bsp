# AGENTS.md

This folder contains the source code for the BSP itself.

## Core Components

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

When making changes to the message handlers, you should always first inspect how SourceKit-LSP handles the requests on its end to ensure everything will work as expected. SourceKit-LSP is available at https://github.com/swiftlang/sourcekit-lsp, but you should prompt the user to point to a local copy to simplify searching code.

## Important commands
- **Debug build**: `swift build`
- **Release build**: `swift build -c release`
- **Lint**: `swift format lint Sources/ Tests/ Example/ --recursive`
- **Format**: `swift format Sources/ Tests/ Example/ --recursive --in-place`
- **Run all tests**: `swift test`

### Important instructions
- When you are done with your changes, always run the linting, formatting, and test commands to ensure everything is correct.