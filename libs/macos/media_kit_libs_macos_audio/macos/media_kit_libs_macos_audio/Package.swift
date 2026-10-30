// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let libmpvTargets = [
    "Avcodec",
    "Avfilter",
    "Avformat",
    "Avutil",
    "Mbedcrypto",
    "Mbedtls",
    "Mbedx509",
    "Mpv",
    "Swresample",
    "Swscale"
]

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.5/libmpv-xcframeworks_v2.24.5_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "af433fcb79c4cb9be5c62465211037f153fd37e0ea406ba209bd391e05d2df9a",
    "Avfilter": "23da3cc71456daf046f3e2313b8323526caed4c1f97d38fb373e2c925df9bf92",
    "Avformat": "bc311a91c838396c4dc4036e6b22f8109fad5d9a7d54160986d1f6159319e10e",
    "Avutil": "c58802e03c78479cb05d420e9b97511511966b19761a7547812b70ec683048d9",
    "Mbedcrypto": "c9581bdd9bf4eff4402aaa41985861824ec49ae345fbe295ea26a736329001fc",
    "Mbedtls": "bfe2bf07f4e70c7937d5ad1d3c46f929b91ddac93d76c412d0c87d261b5131b0",
    "Mbedx509": "1547f48b4c126ce1d284422f4a32abdb38570a8b6e699c0b66b51ed5025cc13e",
    "Mpv": "70daffc5383f0c9b7c5fce116d5d8addb1e22881080d52129de398449a5b4758",
    "Swresample": "a37776295f85d76fdc9eeb4e40ba438c2a76cd831987f05ced246b5b6ce48d34",
    "Swscale": "e991dc139e585ffa11cf215c35fe74e11b03413a56afcd7c91cc70290e49552a"
]

let package = Package(
    name: "media_kit_libs_macos_audio",
    platforms: [
        .macOS("10.9")
    ],
    products: [
        .library(name: "media-kit-libs-macos-audio", targets: ["media_kit_libs_macos_audio"] + libmpvTargets),
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
            name: "media_kit_libs_macos_audio",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
