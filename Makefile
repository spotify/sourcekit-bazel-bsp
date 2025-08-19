.PHONY: release_source_archive
release_source_archive:
	mkdir -p archives
	tar --exclude-vcs \
		--exclude=bazel-* \
		--exclude=.github \
		--exclude=archives \
		--exclude=.bsp \
		--exclude=.build \
		--exclude=.DS_Store \
		--exclude=.vscode \
		--exclude=Example \
		--exclude=.index-build \
		--exclude=.swift-format \
		--exclude=.editorconfig \
		-zcf "archives/release.tar.gz" .
