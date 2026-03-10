"""Module extension to download the sourcekit-bazel-bsp release binary."""

def _sourcekit_lsp_binary_impl(ctx):
    ctx.download_and_extract(
        url = ["https://github.com/spotify/sourcekit-bazel-bsp/releases/download/0.8.0/sourcekit-bazel-bsp-0.8.0-darwin.zip"],
        sha256 = "179670bde96a0da2b41cf52da516b0cd35cb7b2e25113c5e0de7239fc68f82e8",
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
