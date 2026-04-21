"""Module extension to download the sourcekit-bazel-bsp release binary."""

def _sourcekit_lsp_binary_impl(ctx):
    ctx.download_and_extract(
        url = ["https://github.com/spotify/sourcekit-bazel-bsp/releases/download/0.8.3/sourcekit-bazel-bsp-0.8.3-darwin.zip"],
        sha256 = "c9329c4a95126f60fbdc576561ae66b4bc9354b3e2f059e128d1e3a386529bfc",
    )
    ctx.file("BUILD.bazel", """
exports_files(["sourcekit-bazel-bsp", "sourcekit-lsp"])
""")

_sourcekit_lsp_binary = repository_rule(
    implementation = _sourcekit_lsp_binary_impl,
)

def _sourcekit_lsp_binary_extension_impl(module_ctx):
    _sourcekit_lsp_binary(name = "sourcekit_lsp_binary")

sourcekit_lsp_binary = module_extension(
    implementation = _sourcekit_lsp_binary_extension_impl,
)
