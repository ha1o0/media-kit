// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let libmpvTargets = [
    "Ass",
    "Avcodec",
    "Avfilter",
    "Avformat",
    "Avutil",
    "Dav1d",
    "Freetype",
    "Fribidi",
    "Harfbuzz",
    "Mbedcrypto",
    "Mbedtls",
    "Mbedx509",
    "Mpv",
    "Png16",
    "Swresample",
    "Swscale",
    "Uchardet",
    "Xml2"
]

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.9/libmpv-xcframeworks_v2.24.9_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "a1a51f8bd7447ea769d56be6f33882c675b8baa58521cc9247afb5b24cfc725a",
    "Avcodec": "41166e1a6ea239eee60ac98fbb67727e835bed7f6264e3fd8ad985771e972489",
    "Avfilter": "56039b9b52ee82d355906fdde493bb4d1e95b44795c029dbbaffd35fbe38bdc4",
    "Avformat": "a7fb422340f8a8cdc6eb2aec0a5e74258a7981b4edfd6dff7530d06b8cb6bf1a",
    "Avutil": "8c7ddd330102dc0fae0b3f8ec7b5da534cfda18946c1a3c3ea8d20cacf03e458",
    "Dav1d": "473aaee85d0626cb97517f195d6c86e2b14a93b266cee654511247c8446cc9b7",
    "Freetype": "6471ba22d5665df5b077e6b2aba309da24b527362042d707cd6aa2d67650b2ce",
    "Fribidi": "903e8ea7f2c0dca9f207d8ffa66d97eba66b98bf2e77bd670a02efee038191a2",
    "Harfbuzz": "fb172112a4b46b0f7ef9e2fbc84b2ac906feb9ea2eb062dd9d2baddb83315402",
    "Mbedcrypto": "0330b33f44620db5d799f628649d9a601bacacf97e3f30e25f4361a06730ecdf",
    "Mbedtls": "556fc565097f811148f9ea0b08b4dce6a252e971335dc5cc536b43c4810e23eb",
    "Mbedx509": "053d0daa8a6de87e6fb47f512fed1dc817e273053d9e634efb2f61c3d484895f",
    "Mpv": "84e16a8364f94513ede441fc6dc34d064cbeef79fe65a03df30c79879e157e91",
    "Png16": "30dcba463cbfe323abd06875b019db2f6fa7375421c6a86996986e466fdafa58",
    "Swresample": "ddcb8fbf84ef28e1a02d8b72ee57917b9a6d904e2a6407cbfd43f16ee64d47bf",
    "Swscale": "99a4f4fac793b5055d3d824efe2fad6a7ff4c3fea6bda2e2bb6302198d393b39",
    "Uchardet": "4079156af643d3ae9acdf923c9f52cd15aa2c24e7f98d42bf246e14450c65ab4",
    "Xml2": "73209bb1533b6af8dfe80808fbb8a321515b04971ed5b856be045838580031f9"
]
let libmpvProductTargets: [String] = ["media_kit_libs_macos_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_macos_video",
    platforms: [
        .macOS("10.9")
    ],
    products: [
        .library(name: "media-kit-libs-macos-video", targets: libmpvProductTargets),
        .library(name: "Mpv", targets: ["Mpv"])
    ],
    dependencies: [],
    targets: libmpvTargets.map { framework in
        .binaryTarget(
            name: framework,
            url: "\(libmpvArtifactBase)_\(framework).zip",
            checksum: libmpvChecksums[framework]!
        )
    } + [
        .target(
            name: "media_kit_libs_macos_video",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
