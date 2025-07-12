# Example (Cursor)

This is a simple **iOS** app that lets you see sourcekit-bazel-bsp in action. This example and instructions were designed specifically for **Cursor**, but might also work for VSCode.

## Initial Setup Instructions

- Make sure you fulfill the toolchain requirements for sourcekit-bazel-bsp, available at the main README.
- Install [bazelisk](https://github.com/bazelbuild/bazelisk) if you haven't already.
  - On macOS: `brew install bazelisk`
- On the parent folder, build sourcekit-bazel-bsp for debug: `swift build`
- Open the `.bsp/config.json` file and edit `(your pwd here)` to be your absolute path to this folder. Here's an example of how the first argument should look like: `"/Users/myuser/Desktop/Repos/sourcekit-bazel-bsp/Example/../.build/arm64-apple-macosx/debug/sourcekit-bazel-bsp"`
- On Cursor, open a workspace **targeting this specific folder.**
- On the settings page for the Swift extension, enable `SourceKit-LSP: Background Indexing` at the **workspace level**. It **has** to be workspace settings; this specific setting is not supported at the folder level.
- Reload your workspace (`Cmd+Shift+P -> Reload Window`)
- Open a Swift file to load the extension. It has to be a Swift file; as of writing this will not work if you open a Objective-C file (but they will work fine after the extension is loaded).

After performing these steps, you should already be able to see the basic indexing features in action. It may take a minute or two the first time as the tool currently builds the entire project, but you can see the progress at the bottom of the IDE. You should also be able to see a new `SourceKit-LSP: Indexing` option on the `Output` tab of the IDE where you can check sourcekit-bazel-bsp's internal logs.

## Building and Testing

- To run a regular build: Cmd+Shift+B -> `Build HelloWorld`
- To run a debug build, launch the simulator and attach `lldb`: Cmd+Shift+D -> `Debug HelloWorld (Example)`
  - This requires a **iOS 18.4 iPhone 16 Pro** simulator installed as this is what the example project is currently configured for. Make sure you have one available, as otherwise the build will fail.
- To test: Cmd+Shift+P -> `Run Test Task` -> `Test HelloWorldTests`

## Considerations

See the main README for a description of what is and isn't supported at the moment. This project is under active development, so certain features might not yet be available.

## Troubleshooting

If something weird (or nothing) happens, check the `SourceKit-LSP: Indexing` logs for details of what may have happened. If you don't see that option at all, you can instead log sourcekit-bazel-bsp by running `log stream --process sourcekit-bazel-bsp --info` on a terminal session. If you see no logs there when interacting with the IDE, that means one or more of the above steps were not followed correctly (most likely the path on the `.bsp/` file).
