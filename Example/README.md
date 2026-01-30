# Example (Cursor/VSCode)

This is a simple collection of iOS/watchOS/macOS apps that lets you see sourcekit-bazel-bsp in action. This example and instructions were designed specifically for **Cursor**, but should also work for VSCode.

## Initial Setup Instructions

- Make sure you fulfill the toolchain requirements for sourcekit-bazel-bsp, available at the main README.
- Install [bazelisk](https://github.com/bazelbuild/bazelisk) if you haven't already: `brew install bazelisk`
  - Make sure you're using **Xcode 26** as this is what this project was developed with.
- Install [fzf](https://github.com/junegunn/fzf) if you haven't already: `brew install fzf`
  - This is used to power the simulator selection features.
- On this folder, run:
  - `bazelisk run //HelloWorld:setup_sourcekit_bsp_example_project`
- (Optional) Follow the instructions from the main README regarding configuring a custom SourceKit-LSP binary.
- Follow the instructions from the main README regarding either opening or reloading a workspace targeting this folder.

After performing these steps, you should already be able to see the basic indexing features in action. It may take a minute or two the first time, but you can see the progress at the bottom of the IDE. If in doubt that the integration is working, check the Troubleshooting section of the main README for instructions on how to confirm that.

## Building and Debugging

- To build the example iOS app: `Terminal` -> `Run Build Task...` -> `Build HelloWorld`
- To run a debug build, launch a simulator and attach `lldb`:
  - First, select an appropriate iOS simulator via `Terminal` -> `Run Task...` -> `Select Simulator for Apple Development`. The minimum OS version of the example app is **iOS 17.0**.
  - Then: Cmd+Shift+D -> `Debug HelloWorld (Example)`. After building, the IDE will automatically launch your selected simulator and attach it to the IDE's lldb extension.

## Considerations

See the main README for a description of what is and isn't supported at the moment. This project is under active development, so certain features might not yet be available.
