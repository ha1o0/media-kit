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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.23.1/libmpv-xcframeworks_v2.23.1_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "1ff4390467e475a560780c3105d1449884de4be1f94404a8bce18e949084403b",
    "Avfilter": "b41374c36fdb566589219e79cb2d103e4097faa014ef851662650091daef3782",
    "Avformat": "ddbb37170ea8577efeba78d11d8cb557a69017d54fd39b0c1aa9e64e81b1a71e",
    "Avutil": "47484a0d6a2d61eda6b22762a314f8d15247a94a84d18d4bd6ae09d709f75ea0",
    "Mbedcrypto": "fc9b7b28d2696ed97a5ad5bf4de7d117c7a3fcfdac956a488a912072b2ffe9e8",
    "Mbedtls": "e34f58c8312e1d7a040c027932adfabe42b82533fcd84e96095e1c139c5bdf03",
    "Mbedx509": "c2777347bed7fa203b025cd4b72120dcfc3e6d8d3eb63ad99286a5bbe7d39cf6",
    "Mpv": "bf4f04956a90dec77f944a93338f32f3da066b9aacfec566e330316479efd6f5",
    "Swresample": "bad66a16a9a6a5c486cc2e251ee697f3a0b38706e329afa61381158b2193f2bc",
    "Swscale": "c39b9b2faa9ee74add98824854a9951d6df8fcf9f4b0a3e93b0e65613078bdbf"
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
