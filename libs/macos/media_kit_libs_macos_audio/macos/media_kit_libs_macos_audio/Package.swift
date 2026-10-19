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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.22.2/libmpv-xcframeworks_v2.22.2_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "fd23b1fd1e619dabcfd82d8890d953452c2b0e7c365461527aac6fdef842c905",
    "Avfilter": "27e46f8b04ee04a61164bf919d4e0836589ccd9bbe0f204aa36bcf826b299e42",
    "Avformat": "1eb894714029542915dee33ced2f1567960df26542ab9c0dd6ee61c24b5322db",
    "Avutil": "c6ab222d298c5ffb21fba3c2b639c7dcae17d3cdf2e7ae2711238b564c2b2216",
    "Mbedcrypto": "32c0124ebff2fec272ef40b68162de2c20587c3fff357d6ebe63554489da9c37",
    "Mbedtls": "be2144fba5cc57a7df0f45da2ebae83b3ad862861f8b8f1682241c97e9482b2b",
    "Mbedx509": "11e4729e421bb0efdf3da79a73986cc089bf402cde4e9d0981756cd0af868c94",
    "Mpv": "7442d2b66a8bee88fd27a489f99fc8a4df55028a9fab168b036d15fe80c16762",
    "Swresample": "7fc97a3690dc79b4d2c69d1a20e660ed445da0af895949af27f02939f8bb42a5",
    "Swscale": "f89a7d7cce6695af162340db5db868fcc864570680879d1f5e92c89a21ea7443"
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
