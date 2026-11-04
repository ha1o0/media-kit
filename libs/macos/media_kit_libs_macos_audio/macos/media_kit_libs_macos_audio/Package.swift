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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.9/libmpv-xcframeworks_v2.24.9_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "0dbb946e77b82917c637c2b9e171238361ceac9e6d19248fecbfc22a5c31e5cb",
    "Avfilter": "e2e5d4d41b39c2ce55d288402337d6b1ba5973d744c8722fb10541f774a84a8e",
    "Avformat": "ab8a2d370c9fdc87cc13839aa41beb18f9500086f3d6b224f68c36829e5ccad1",
    "Avutil": "1f1753286ec9c8d00db0b08c569515ffc644da4d8d8840b0ff61ac89be4f66bc",
    "Mbedcrypto": "bc35650d1ce79038bc57efed415afd5bb5c52456d71428b2d21aa8e435a487e6",
    "Mbedtls": "8dba8649fa9936fb3ed44cc678debfc437dfb48e6df4f7c3b245e0e377fa5eef",
    "Mbedx509": "0a51cf17a445a1fb950d8e17a02a122e3f83469330d0de2355c02ad3b1b7b8eb",
    "Mpv": "0e29748136965f35c42f1d5c5f14fb22ade3643ca066c0c64e267a285a85cb84",
    "Swresample": "160151d1451e97b859bf97a1425aa8647bf5026b5650cd1ac964cf06002b006d",
    "Swscale": "e177acb8d97863426c00b789fcaa35343a5710715ee1d28e3c983178e8419965"
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
