"""Module extension to download the sourcekit-bazel-bsp release binary."""

def _sourcekit_lsp_binary_impl(ctx):
    ctx.download_and_extract(
        url = ["https://github.com/spotify/sourcekit-bazel-bsp/releases/download/0.8.1/sourcekit-bazel-bsp-0.8.1-darwin.zip"],
        sha256 = "854fb47e59c8e5e292f4ab9e7a61caa2b1d09d224b6a1ff3ac29637f1a4b5192",
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
