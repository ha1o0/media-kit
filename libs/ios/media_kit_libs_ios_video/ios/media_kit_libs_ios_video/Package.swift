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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.5/libmpv-xcframeworks_v2.27.0-ios.5_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "c3349204a3381205771f779574f43869fa00035ff7a55ec305703f5d70e345d9",
    "Avcodec": "42e40ddbb2ec19a80a14288ad4cb4d4a635523526d9c6905362eb128b1733b5a",
    "Avfilter": "405559008561a725faaa9adacff912518a75d47cb0caaf4a7b7c8cf4143ced39",
    "Avformat": "bff52ffb85abafbe4743d45fead76422af8903515fcfe0b0c6057316b2af991d",
    "Avutil": "5eafb19bca7f94c356307864bf518892428dd6b66567cea84dcb8f60c0da976e",
    "Dav1d": "391ccc517671477f6650c88c376c37b290d92f9cb65687738eef5ff2b22505ed",
    "Freetype": "f014eafecaf0b594e5fc37fbb0ff146d2c1ae2cf176b72fb6ef69fa36cfc2c96",
    "Fribidi": "acb301f4fe58ea7a3b193cb2fbe688015aed5fd1c6bac1c950c9e6330fd1f4f1",
    "Harfbuzz": "39d8ff7dbead9564e1368d4189d717ce23d25a7044ff987024b1f709daf3fa5e",
    "Mbedcrypto": "e1ff870e0a1edbf404e582fcec598acb60b35755ffaad8b11e0b0fe431ce7eb5",
    "Mbedtls": "c260c426cbfb9af1685a3e5c28b39ff1eae5dac5ee1c83d8b2a1a3b9e43a527b",
    "Mbedx509": "ec69c57f509aeb8364671c5ae36f8ca820bfa61d2d8eac65681da7785ed39e41",
    "Mpv": "880110863a2abfa9ed64ef9d40520ce5f5edb1a19b0916520e47c330e7a56cd2",
    "Png16": "0148119d81c8e7e0d14a9f629447d12fcf5443982cdaf82356a4a7ef6cc8bc4d",
    "Swresample": "7d03df914ca80642ea189b02342c3aa662917d124dd660f711bbf3c3416221f2",
    "Swscale": "f8163387d8e52b4cb340d667120e3a99088c8357a4b05b80c619ada19fd1962a",
    "Uchardet": "8520614f66bba7a6f9fa9aef9103bfff62303f2ccce20b8d8f32cf0343e84e5f",
    "Xml2": "ce238fe5aa89bcb15035ac6af9c5738633cba491cf6ab5dd006cc5fd32650e42"
]
let libmpvProductTargets: [String] = ["media_kit_libs_ios_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_ios_video",
    platforms: [
        .iOS("15.0")
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
