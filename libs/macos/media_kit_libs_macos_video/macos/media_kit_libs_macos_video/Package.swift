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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.22.2/libmpv-xcframeworks_v2.22.2_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "309fb9751414dc9bda5004f814c33a74923990cc976ba18d928423d7990d3ff3",
    "Avcodec": "8474e8cc80185e5603f5e598a855103f8a390422f8f58eb717a9bc0ef46861e1",
    "Avfilter": "eb68848912775e0a81a2c914d2dd1600d6526465868c7188f1693bc76517b524",
    "Avformat": "76616d5bd62197e4c646881a7d49f8f59755fa3a297f62349097e6a517eeb3ff",
    "Avutil": "04ff2202592c2f80b5724fe214e743bd39362d11c7cb2533285be99d67a82f5f",
    "Dav1d": "ba4499822b72ac8f0a437f2cbec699f219a6949b2d7cfbcaeec97eeeb6fa0fb6",
    "Freetype": "cf5681912c2b804d6f9380ff543d2b78d9dbe0fb0f12cf91ff9259357992f7ec",
    "Fribidi": "51c4283a8024a5d621e3a646919a392ec43b7462525827ad42f97f5d175fa7fb",
    "Harfbuzz": "27dea16e1479ca195fed6c55ba0b2c1bf99a19c7dd9104af5475eac25401f849",
    "Mbedcrypto": "2ff1236b7d24cd1f7bb2a9c3bf50d4de78e58481f0b437321e93df8d38c14c7c",
    "Mbedtls": "1bf9cd707ef55ef928f83d6b4b4f6efb5c10f19fced4b15d4d9ed7a0dc26dcb2",
    "Mbedx509": "3ef6c568426cb30a51218fba789863366aab3043fbd46fe95c8e493251cb8b85",
    "Mpv": "e67c0f3dfc51d5df18f80c6385b2bf7eaafdddaf53a8ba2bc13f05de0bd5d1ed",
    "Png16": "ce89df1a75bd0288d5599e93ebfd9a17ff19dc26bbbd2f76558c944865099949",
    "Swresample": "ab4fdc92e7340d80ad643457020b3d9b1963a7ea68913ad322e9331a2ea5e219",
    "Swscale": "bf6e0a61f41c47bc0aff07e835c61a23095ba97211681e9ec46bfbe350ea6269",
    "Uchardet": "5d686427d85d15ee5726857d1947201afd6b538323f8ca55d0fe2add3bce7f3c",
    "Xml2": "b24a41f572698298d54d7ffef946506ee51d2854bfcc2ce52cef4b44a0b90cea"
]
let libmpvProductTargets: [String] = ["media_kit_libs_macos_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_macos_video",
    platforms: [
        .macOS("10.9")
    ],
    products: [
        .library(name: "media-kit-libs-macos-video", targets: libmpvProductTargets),
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
            name: "media_kit_libs_macos_video",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
