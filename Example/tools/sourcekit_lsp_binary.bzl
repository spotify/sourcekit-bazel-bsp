"""Module extension to download the sourcekit-bazel-bsp release binary."""

def _sourcekit_lsp_binary_impl(ctx):
    ctx.download_and_extract(
        url = ["https://github.com/spotify/sourcekit-bazel-bsp/releases/download/0.8.2/sourcekit-bazel-bsp-0.8.2-darwin.zip"],
        sha256 = "84f92cc4a6fd17c55594fcf00bc4f287d9e1ff726ad3126ebb9f686b93505d10",
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
