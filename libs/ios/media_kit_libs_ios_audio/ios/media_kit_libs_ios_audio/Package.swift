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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.8/libmpv-xcframeworks_v2.24.8_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "687091c1b40df9be2a7ee6304036ed01adfbfbc354018906540ffd17e44a37e2",
    "Avfilter": "af64e1838292239cf3b2571695f66267708b490e7224a01f79dc003ec9838106",
    "Avformat": "6ae89cb7bbb8c979983353a771ae435b7a7747b26e2a8e53897f0b753cd0b2d6",
    "Avutil": "7dd4197b7d9131c8cfd570cfc7fe76c809396370e8c4937a050e81183068b5d6",
    "Mbedcrypto": "a4f9c6cd580f48cef349ed7555bec0152b4b269c68a43aea3faa3ea71ed528a6",
    "Mbedtls": "f5ae27811a6044f67fb0eb083d86a587430a604984db194fc9ac1907cd0914af",
    "Mbedx509": "2b4bc489da7be2c14e7579f4a73715c95e4fffbc0402341d84ffae1180540938",
    "Mpv": "6b1b741e8815b74195904cda7a46d5b8b52718c03f8518f0955c4122ac29bf68",
    "Swresample": "cdc1ca35bbe0f9f7e49a90594e8ffe9a3345a05693d1d870b0fe2d73fff234ea",
    "Swscale": "eff69b05c16e770edeefeec29ba60914f585bd16cfaa235a546dd6da59378d7d"
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
