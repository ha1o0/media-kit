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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.11/libmpv-xcframeworks_v2.27.0-ios.11_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "3a42d67f73fce5346d65855b8bbfc2fcfeb45cc6c1378f22cdc9b494158b4369",
    "Avcodec": "3259da1d7fad678ef7a6fc73679727e7663888a24259814dae929dff66b1da6e",
    "Avfilter": "331f9438e56908bb1a52ba0666a31499c6fa2e767ba032bdafb1cff0e8ee0806",
    "Avformat": "518bae3ac667adea7ec0c15098d3dfe902f4b1219d22256d2150961af3a82d4b",
    "Avutil": "f0204bb0d7a3cc1a44d1fc47c00167af2cdbdc919ba129c4b71d01e76fa9fe48",
    "Dav1d": "aac9893b5aee69420576544f78fd3c4b337290714871e3939c71c789c4cf0d2a",
    "Freetype": "a558d9e67c3b79f8db798f3fdbb360313c3cd6457b70adb93343f8a1af9ea385",
    "Fribidi": "a696189146fb60d51654376f3789ed3b03114dc76e7c3058c95ac4af44f9fce0",
    "Harfbuzz": "da157704a7e98f2d72970698d2e8366af94e7898fa9da6a0d594cef871ff3ff7",
    "Mbedcrypto": "ef6501526db378c64332d6d69048e389b8f63cc2899fb29cb37fea9ee3305c84",
    "Mbedtls": "9790ed001cb6f30cb3571ee95ccd6b3c8dca673c2eec89236c280dd0b3f96333",
    "Mbedx509": "582ebc75e34dfa34deb1f6f3506003aade15f3cd46fb1c5f1916d78b2ba23f57",
    "Mpv": "33894ca221ee814cd6752b3221e60292c424172b8499ea45797781e69395e974",
    "Png16": "25294eacee719c1b71b6c772237ec7539bb117296d238a55d5f968c0dd076c17",
    "Swresample": "44e29a354d79fa4a031f8769529910b3fe3ef46f62da0202fff26c7ae80d391f",
    "Swscale": "54d8894e413ab4795973ea804fb724cd771f0bd8f8294117e9ecc1e63d3e5a9c",
    "Uchardet": "61d78838b515abda471aaf64b88d1ba0c0a6473e26d41270dd4bf38c7f0eb5c5",
    "Xml2": "41eb376d9c47d9f815cc7be986c9e5795dc5e93ee90a467c7db5b1125535f0da"
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
