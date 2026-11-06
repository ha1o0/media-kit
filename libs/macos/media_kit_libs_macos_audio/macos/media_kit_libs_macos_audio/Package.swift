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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.25.0/libmpv-xcframeworks_v2.25.0_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "74c85c342da8e62529766c5378c970305399c03001583c631a785f21bf2e5bcc",
    "Avfilter": "7cd514255ef0ff5ada530731d7b7d85e19ec647e4be8a9c2235532627d1587be",
    "Avformat": "fda5618ef004ea8ad51c6ec3284b8bd540d27c52a5f9e74392ae078120a120e5",
    "Avutil": "d8be67ffbea1e7d8a98437cae781b3ea6929da123ecc7088b25738a77367555c",
    "Mbedcrypto": "7a628f2fc6916a7295d3bf72a556812001286446d749b699c8e644d0f16913c4",
    "Mbedtls": "7ca06b84a45feb4c026fd8e2630ffee87d15c04a12dc59d5b3aad52797ea7405",
    "Mbedx509": "35463141a86673ed7b5604315c48b503b659a6739b87ab2734b3ff2efb2861c3",
    "Mpv": "f94fd52a41098df4a3b30e7578427bc32ae1ebbd3caf094561317fce3bd8c30e",
    "Swresample": "b1d9f7de3d8339e7dad87b4199dfcd37d6bff0aecae9e627ca6cc90e36dcd869",
    "Swscale": "54dd83350fc9e907aa62d52d8139be8bd082eb5bfe21610ec4770d880f0e57f2"
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
