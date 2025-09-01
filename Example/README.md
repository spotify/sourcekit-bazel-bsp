# Example (Cursor)

This is a simple **iOS** app that lets you see sourcekit-bazel-bsp in action. This example and instructions were designed specifically for **Cursor**, but might also work for VSCode.

## Initial Setup Instructions

- Make sure you fulfill the toolchain requirements for sourcekit-bazel-bsp, available at the main README.
- Install [bazelisk](https://github.com/bazelbuild/bazelisk) if you haven't already.
  - On macOS: `brew install bazelisk`
- On the parent folder, build sourcekit-bazel-bsp for release: `swift build -c release`
- On Cursor, open a workspace **targeting this specific folder.**
- On the settings page for the Swift extension, enable `SourceKit-LSP: Background Indexing` at the **workspace level**. It **has** to be workspace settings; this specific setting is not supported at the folder level.
- Reload your workspace (`Cmd+Shift+P -> Reload Window`)
- Open a Swift file to load the extension. It has to be a Swift file; as of writing this will not work if you open a Objective-C file (but they will work fine after the extension is loaded).

After performing these steps, you should already be able to see the basic indexing features in action. It may take a minute or two the first time, but you can see the progress at the bottom of the IDE. You should also be able to see a new `SourceKit Language Server` option on the `Output` tab that shows sourcekit-lsp's internal logs, and after modifying a file for the first time an additional `SourceKit-LSP: Indexing` tab will pop up containing more detailed logs from both tools.

## Building and Testing

- To run a regular build: Cmd+Shift+B -> `Build HelloWorld`
- To run a debug build, launch the simulator and attach `lldb`: Cmd+Shift+D -> `Debug HelloWorld (Example)`
  - This requires a **iOS 18.4 iPhone 16 Pro** simulator installed as this is what the example project is currently configured for. Make sure you have one available, as otherwise the build will fail.
- To test: Cmd+Shift+P -> `Run Test Task` -> `Test HelloWorldTests`

## Considerations

See the main README for a description of what is and isn't supported at the moment. This project is under active development, so certain features might not yet be available.

## Troubleshooting

If something weird (or nothing) happens, check the `SourceKit-LSP: Indexing` logs for details of what may have happened. If you don't see that option at all, first run `Cmd+S` on a Swift file to see if that does the trick, and if it's still not there, try logging sourcekit-bazel-bsp directly by following the troubleshooting instructions in the main README.
