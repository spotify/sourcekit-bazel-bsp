"""Module extension to download the sourcekit-bazel-bsp release binary."""

def _sourcekit_lsp_binary_impl(ctx):
    ctx.download_and_extract(
        url = ["https://github.com/spotify/sourcekit-bazel-bsp/releases/download/0.7.1/sourcekit-bazel-bsp-0.7.1-darwin.zip"],
        sha256 = "af74af127d1bc61573235a760d6c972fd70f15fc51874da39287468f8ca590b4",
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
