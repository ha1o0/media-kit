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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.26.1/libmpv-xcframeworks_v2.26.1_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "0a9d9815b612922488303543874e9a5083c72ed3bd1ded1cc986f866d52a4fbe",
    "Avfilter": "72c3df8e7b12aace6ce7d20163dbbd8e6f8a352ed5ba7d59e1e00bfeccf9f90c",
    "Avformat": "744829b337b106b02f107890c04e0d4359f8db476e148cbf0f474b188b11aee0",
    "Avutil": "d3277b10438e777912082299e0a7b09c3dc976cb27fc8e6bd8189d432115a619",
    "Mbedcrypto": "7380639efc5bd1e509a89ef9bc72c99f7085245ec22871f8d14828e9a5f2e603",
    "Mbedtls": "22a6811535f0e4730213b494e8c78a5667bae068b4fa200a6c6c45e228b455cd",
    "Mbedx509": "afcc4e863731b6dc2bbcc709750f81b54275f97fd4b2be457916449271eb9dc7",
    "Mpv": "852fa799cc294893631c97ae6b4d9327814341e4b4ad63149a80cf5fc526dd75",
    "Swresample": "0eca9ff0c51d3d29cad0e7fc91264e07d1fb3ee7e78850146a457551aff9f152",
    "Swscale": "c272917969faa72bef294dfc3394b042ae118079d7a44a4ad5c8cbd2dab12caa"
]

let package = Package(
    name: "media_kit_libs_ios_audio",
    platforms: [
        .iOS("9.0")
    ],
    products: [
        .library(name: "media-kit-libs-ios-audio", targets: ["media_kit_libs_ios_audio"] + libmpvTargets),
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
            name: "media_kit_libs_ios_audio",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
