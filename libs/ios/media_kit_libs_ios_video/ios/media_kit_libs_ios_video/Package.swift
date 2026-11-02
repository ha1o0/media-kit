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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.8/libmpv-xcframeworks_v2.24.8_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "d2fbf823f5f2ca132f7f9f0080d89c1e0139596d503c88b47c9e1896bf1668e1",
    "Avcodec": "4f96d3d799588416f3a876d14b231c74daa3f9c621c8deeadf5d7804e1aa34b8",
    "Avfilter": "a572af2553879712ffa390aa8e6bcc841d9d8bf2ac28edc114602d4f0d410d15",
    "Avformat": "2a7d68307321cf2c1f044fa03244e455637957ab852de9284bb1a4d5521b4908",
    "Avutil": "dee313a87134701a21244e6edcb646d1a9848813d51ab4b274a909198c95133c",
    "Dav1d": "1ebbd360647035f03bf5b80ead4594a7734ba293e21d730022968cba04f2e6f1",
    "Freetype": "19c96544340bf01e6c43b36ebb64e70cec3e0a70dbb575a5f1d237f2c24774a3",
    "Fribidi": "3c786c169af76cada569b7ccde00b3c522de8cf2604c6d1750e790fdc4b3e06d",
    "Harfbuzz": "582162a12c7354a7c6ffdd2e778d7a7d1f818b051e05b269342541fd7313dd2e",
    "Mbedcrypto": "b570b1426a1761e34aae6a7320735e74c2888d3385bfa32ad529463dc6209a8f",
    "Mbedtls": "ec2e67e726fea3da0507db13a0a30e38c44ee9cde5c8978c2cbc8f4375b0cecf",
    "Mbedx509": "d54971b7fabae38fe91e7049cddcbd529d4ece5ba08475345fe7a1c27c2eaaba",
    "Mpv": "8300d5338dc587cf63b22bec8bfabacf3aba7d947116ef47e15ada5e2b3867a3",
    "Png16": "66c00e6cd5fc55a2f9be86f58b93ceb29428e482eee8b36d5e360f57723e6921",
    "Swresample": "f96b5e6db711611ae4c7aa6a681a8a8ae305d938e320dd13d540ab66b9b69b5b",
    "Swscale": "1a5db7cc5fbf44177adf8bf19856f7b5774c4a91a973d317cdc55103fd41a3df",
    "Uchardet": "ceced5c0699e4bf3de738e4e12dd54018224ca4c1e67c851687d32f7a3652890",
    "Xml2": "4c9883393b192fd2d5e3f6ad74fdc2114ce810d450bff9f5ee7b5de854fe4129"
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
