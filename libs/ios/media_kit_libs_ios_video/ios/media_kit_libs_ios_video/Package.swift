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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.3/libmpv-xcframeworks_v2.27.0-ios.3_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "64f0e19ad03b1a5161ffce49c48f5c1ecb53ab071c146f575a4ec81a0e080ca6",
    "Avcodec": "74f74b5f690d0c61744383b33846a74a4912ee2c44b426afb33da6ba8cb81127",
    "Avfilter": "25e9e9591272140cc21e3afd3a491dcb357ce1c4a7a22d304c0224d11a052984",
    "Avformat": "d7d41dc71a38257f88d5ee4747d59de080cfc248f045a7eaa47b47e985d97b58",
    "Avutil": "5bf6db8204604554ae198b18c24cf57d4a437eb1497908f8d70ed6a44fee1249",
    "Dav1d": "3eab50dd1d2077671a35a54e625c100b28a65f8d156cdec29c78846b518c6464",
    "Freetype": "9d0eb5c2b03ec7de07e6a6afc9c2c3a4c890407eb1a3162feb759bc13bc657f3",
    "Fribidi": "0e5e3dfd1d2e3882af88386ca700b7a089432b897508f9b803ebe8b59e8b97b1",
    "Harfbuzz": "44b3321db812be159da8a3f089988840a72bf98fbbec3e62934ffbee2d2bb2ba",
    "Mbedcrypto": "653267b129631bd816ccc5681acd48b89aa5c56d2264279c16219535d2d87de8",
    "Mbedtls": "ee9c2d2e572fdf576a93dd3e3b7e916d159af8e4015b1063bca9ec66a89dddbe",
    "Mbedx509": "bfd16445f415eaee097deff4d4da8ea66786a5dc56d2bc2cad7ced418e8d4543",
    "Mpv": "49f2dd0595e938b900b34e73e4cbb30f566381f73c11665590c333be808d1295",
    "Png16": "7404c7a4ef6008d722d8d3d935c7fa7dfa3ba23bb88fddefa820673383031953",
    "Swresample": "cfc973907950e5a5c254004524965829a98b3c7ea633813e78bd654482779b4f",
    "Swscale": "4f6331981977b1ab3b9855b1c51d866e858a18659bc00104434260e33a54b766",
    "Uchardet": "2b5d3e275e7f5c4aff02fc762c64455150aeeaab7b13d38eea4699d1de92bc5f",
    "Xml2": "c4e7cfac2c0f3d1aaf91a67261ae037e12526eebb8bc6f0157db3de0413acfff"
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
