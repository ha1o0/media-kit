# Update Darwin libmpv pins

Run `update_darwin_libmpv_artifacts_full.sh --platform macos --version TAG --dry-run`
or `update_darwin_libmpv_artifacts_full.sh --platform ios --version TAG --dry-run`.
The platform and version are mandatory; platform-scoped release tags for the
wrong platform are rejected before looking up release metadata.

The default is the video package. Use `--variant audio` or `--variant all`
when the release has those artifacts. The older `update_darwin_libmpv_artifacts.sh`
entry point retains its default-flavor mapping. `--repo OWNER/NAME` allows an
explicit older release source (for example `ha1o0/libmpv-ios-build`).

Remove `--dry-run` to update the chosen platform's CocoaPods Makefile and
SwiftPM checksum pins. All required assets and checksums are validated before
writing anything; the other platform, all existing caches, and the current
checkout's build outputs are left alone. The normal app build downloads a
newly pinned version. Existing tags are immutable; a different payload with
the same tag is refused to avoid reusing a stale CocoaPods cache entry.
