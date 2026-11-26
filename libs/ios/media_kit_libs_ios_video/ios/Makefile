all: .cache/xcframeworks/.selected-archive

MPV_XCFRAMEWORKS_VERSION=v2.27.0-ios.15
MPV_XCFRAMEWORKS_SHA256SUM=2e8a93d7005a4294916cebe9c1eb79dc9f4367ca3036fc1e6f44735938be036b
MPV_XCFRAMEWORKS_LOCAL_ARCHIVE ?= $(wildcard local_libmpv/libmpv-xcframeworks-ios-universal.tar.gz)

ifeq ($(strip $(MPV_XCFRAMEWORKS_LOCAL_ARCHIVE)),)
MPV_XCFRAMEWORKS_SELECTED_ARCHIVE=.cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz
else
MPV_XCFRAMEWORKS_LOCAL_SHA256 := $(shell shasum -a 256 "${MPV_XCFRAMEWORKS_LOCAL_ARCHIVE}" | cut -d ' ' -f 1)
MPV_XCFRAMEWORKS_SELECTED_ARCHIVE=.cache/xcframeworks/libmpv-xcframeworks-local-${MPV_XCFRAMEWORKS_LOCAL_SHA256}-ios-universal.tar.gz

${MPV_XCFRAMEWORKS_SELECTED_ARCHIVE}: FORCE_LOCAL_ARCHIVE
	@test -f "${MPV_XCFRAMEWORKS_LOCAL_ARCHIVE}"
	mkdir -p .cache/xcframeworks
	@if test ! -f "$@"; then cp "${MPV_XCFRAMEWORKS_LOCAL_ARCHIVE}" "$@"; fi
endif

TAR=tar
TAR_WILDCARDS_FLAG := $(shell ${TAR} --version 2>&1 | grep -q 'GNU' && echo "--wildcards" || echo "")

SED=sed
SED_INPLACE_FLAG := $(shell ${SED} --version 2>&1 | grep -q 'GNU' && echo "" || echo "''")

.cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz:
	mkdir -p .cache/xcframeworks
	rm -f .cache/xcframeworks/*.tmp .cache/xcframeworks/*-ios-universal.tar.gz
	curl -L \
		https://github.com/ha1o0/libmpv-darwin-build/releases/download/${MPV_XCFRAMEWORKS_VERSION}/libmpv-xcframeworks_${MPV_XCFRAMEWORKS_VERSION}_ios-universal-video-full.tar.gz \
		-o .cache/xcframeworks/libmpv.tar.gz.tmp
	shasum -a 256 -c <<< '${MPV_XCFRAMEWORKS_SHA256SUM}  .cache/xcframeworks/libmpv.tar.gz.tmp'
	mv .cache/xcframeworks/libmpv.tar.gz.tmp .cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz
	touch .cache/xcframeworks/libmpv-xcframeworks-${MPV_XCFRAMEWORKS_VERSION}-ios-universal.tar.gz

.cache/xcframeworks/.selected-archive: ${MPV_XCFRAMEWORKS_SELECTED_ARCHIVE}
	@set -eu; \
	installed=1; \
	if test ! -f "$@" || test -z "$$(sed -n '2p' "$@")" || test "$$(head -n 1 "$@")" != "$(notdir ${MPV_XCFRAMEWORKS_SELECTED_ARCHIVE})" || test ! -d Frameworks/.symlinks/mpv; then \
		installed=0; \
	else \
		for framework in $$(sed -n '2,$$p' "$@"); do test -d "Frameworks/$$framework" || installed=0; done; \
	fi; \
	if test "$$installed" = 0; then \
		framework_tmp=$$(mktemp -d .cache/xcframeworks/frameworks.XXXXXX); \
		trap 'rm -rf "$$framework_tmp"' EXIT HUP INT TERM; \
		${TAR} ${TAR_WILDCARDS_FLAG} -xf "${MPV_XCFRAMEWORKS_SELECTED_ARCHIVE}" --strip-components 1 -C "$$framework_tmp"; \
		test -d "$$framework_tmp/Mpv.xcframework"; \
		mkdir -p Frameworks; \
		rm -rf Frameworks/*.xcframework Frameworks/.symlinks; \
		mv "$$framework_tmp"/*.xcframework Frameworks/; \
		mkdir -p Frameworks/.symlinks/mpv; \
		${SED} -i ${SED_INPLACE_FLAG} 's/\r$$//g' create_framework_symlinks.sh; \
		sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv; \
		rm -f .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz; \
		ln -s "$(notdir ${MPV_XCFRAMEWORKS_SELECTED_ARCHIVE})" .cache/xcframeworks/libmpv-xcframeworks-ios-universal.tar.gz; \
		{ printf '%s\n' "$(notdir ${MPV_XCFRAMEWORKS_SELECTED_ARCHIVE})"; for framework in Frameworks/*.xcframework; do basename "$$framework"; done; } > "$@"; \
	fi

Frameworks/*.xcframework Frameworks/.symlinks: .cache/xcframeworks/.selected-archive

.PHONY: clean
clean:
	rm -rf .cache
	rm -f ./Headers/mpv/*.h
	rm -rf ./Frameworks/*.xcframework

.PHONY: .cache/xcframeworks/.selected-archive FORCE_LOCAL_ARCHIVE
FORCE_LOCAL_ARCHIVE:
