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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.2.0/libmpv-xcframeworks_v2.2.0_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "843e969440dff5f293c6f7877f24813f59ca0807640b76df8606c1b9a0f9ca73",
    "Avfilter": "973afce3c2125d23ee46e61556a0125839d3f26b845c2e8fb3326c5e4bd0b552",
    "Avformat": "4ff02d6c8615828604f9a849f12b6834d2b19f8704bf24f9078a16757a3d800d",
    "Avutil": "96235db73bd76600113f30fe9edfd24c196ac9cc28995999b82115f4c43b12e8",
    "Mbedcrypto": "a92a0cbfed1f6117a58ad288a4124afa33de30399644c78b39b38dc758ad760c",
    "Mbedtls": "6365be537f0df960e7f14129f65967b5e51392c6e3f86980718e6bf5b0df9ace",
    "Mbedx509": "2c0a6da41cf1d9bce79d2ab73cb1d981b43ba3533c9d648980134a2d753ddba0",
    "Mpv": "67855b3a8b4ae5ef76526c18fcedc0ec853f4581263913de5f1a582dde56d9e9",
    "Swresample": "e5747ab47678696d733c21175e1ce33147a9288e745992a37e140811bfb16d35",
    "Swscale": "615494fb712d5cd5c90fd988dd1d5eafc03471e0dd30f33b2ef957a66dc1ff3b"
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
