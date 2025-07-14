# Contributing

Conversations around the development of sourcekit-bazel-bsp are currently being hosted on the [official Bazel Community Slack](https://slack.bazel.build/). We are over at [#sourcekit-bazel-bsp](https://bazelbuild.slack.com/archives/C093CHNUYV8) and everyone is welcome to join!

## Xcode

If you're using Xcode, you can develop for `sourcekit-bazel-bsp` by directly opening `Package.swift` file in Xcode. After building, you can test your custom binary by changing the path to sourcekit-bazel-bsp in your test project's BSP json file as described in the [Initial Setup](https://github.com/spotify/sourcekit-bazel-bsp?tab=readme-ov-file#initial-setup-instructions) instructions.

## VSCode / Cursor

Download and install [the official Swift extension for Cursor / VSCode.](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode) After this, the IDE should properly recognize sourcekit-bazel-bsp as a SwiftPM project and automatically generate the relevant build/debug actions. After building, you can test your custom binary by changing the path to sourcekit-bazel-bsp in your test project's BSP json file as described in the [Initial Setup](https://github.com/spotify/sourcekit-bazel-bsp?tab=readme-ov-file#initial-setup-instructions) instructions.
