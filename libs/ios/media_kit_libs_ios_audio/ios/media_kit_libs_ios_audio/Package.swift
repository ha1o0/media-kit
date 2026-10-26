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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.23.1/libmpv-xcframeworks_v2.23.1_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "80bd39fac761a839a43cf8603e37cb80c7ad7062a2f535eca72432f8f38793a3",
    "Avfilter": "07b4ea6b04be57f28a1530c26ef0055c3dcde1c2b82fa58b198b8a94ff4e6fb0",
    "Avformat": "1be7ff5159c819d474d1ac3456df3c5a308f6866df71a33db29b2fff7deba739",
    "Avutil": "e84d524b15e71aff64f5fa9949918e6d7e93fed9c12088d2284de9bee399c39f",
    "Mbedcrypto": "5c5be367ea70b356fa03338607be43dd8d67db4a521efaa433433b0deba3d2d9",
    "Mbedtls": "6c18c39b3c131c045362992e53a1e0fd0f5b2e94395aaded8911af38f664ed8c",
    "Mbedx509": "e6e4c7f582fe8f5ccce5842efca2ca0418b9236f7b6c1c209cb7a040aa233cfe",
    "Mpv": "f6c283318eec44ca4de30e4915ca1764844fe44e3410b0aedcb865ac0fc7dd02",
    "Swresample": "d2f4268911853155efa0d95f28752f9d85603f15ada4885250ed2c410160e1a1",
    "Swscale": "0810cde88fee12aa4a24203aa22ff6aaf0446aa4d036b89b5780ad31573ee7b4"
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
