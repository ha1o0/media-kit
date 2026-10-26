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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.23.1/libmpv-xcframeworks_v2.23.1_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "844f17ca9e3e913800f3da7e73bddb767b67cf6b6a7bf68fce3f89821c38175a",
    "Avcodec": "7f0ff38c9eb106537147b7eeee7da24a979a2bfe9d0f83ee6fe2cb9f125a7f2a",
    "Avfilter": "1dbc781e3cda293ec97441cbec3c5c745554f7c4de12e1bf84d1c1806a663387",
    "Avformat": "a06ce55b953884db131ea03f697a9702adf9da0646ad4713e44bf5f75b1f2149",
    "Avutil": "9fd31c915f90ced5269e65cbc9a5361e18bf5c796b620d2af71ac5550835ac4c",
    "Dav1d": "1ccc04beae4924d73215f0a80bec6c2f9d568a353e249030436468d101860711",
    "Freetype": "ed7c846a8278ac11fb1da5f2405d250c1a3414069024c39f70b32b9159ff03da",
    "Fribidi": "8b41a0086da361f9ffab672f24adb0e466e52ae8be92a2a5e579c14dd08bcf42",
    "Harfbuzz": "b3218c208735b170670dbb64fd30bc49cf34db5c0840f6dbd9f0fda4b5dd4557",
    "Mbedcrypto": "758394dcb8b554bf5f0c3d50fda0406fe7afc15f1023c2b4962d6266a72d5ab1",
    "Mbedtls": "b722fc93619796d11e8a6d261d250bda2c8730abdec814712861ba61cd2d66c4",
    "Mbedx509": "791318c9a20c09e46dfc42459323efc434b7c2ca4f4be3ad5e6e75f0057e8959",
    "Mpv": "05212c536a27fc1430ac8abdb6ae7770e6d7595a0f3fcc8fcc3803ff03fd1b1e",
    "Png16": "ee91229a1c9ffc58a0cb168a5465a18e8fefdd61b2cbcc519d50bd32c387f202",
    "Swresample": "5e12e207a093d9b26ed327f8934841ee4f57964fb5ad785e90deda910c401604",
    "Swscale": "83ee57b84732508b6cd2a5167b6b50dcc72c18ae857a4ed21ea008b38c53da40",
    "Uchardet": "cde99990aba7d7d5fe438b062094839a9a997847d2856fe57416e7ec07a9c957",
    "Xml2": "efe29160849ea5e32d36f0285ff64e20500ef327fa46068d84322c25682a3032"
]
let libmpvProductTargets: [String] = ["media_kit_libs_ios_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_ios_video",
    platforms: [
        .iOS("9.0")
    ],
    products: [
        .library(name: "media-kit-libs-ios-video", targets: libmpvProductTargets),
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
            name: "media_kit_libs_ios_video",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
