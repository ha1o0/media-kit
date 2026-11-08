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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.26.1/libmpv-xcframeworks_v2.26.1_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "abd0105965afcdb26bafbed4f0007dc9091d6774d497ce0adc48c61ad704c0f0",
    "Avcodec": "425ef024eb8b430c2a0eedabaf0b699d51a0395a955263a8b01295267db33a41",
    "Avfilter": "5c45ac5077d5ca5451487bd0596cc42917afb67b2f5dffb831feaae14e17e03c",
    "Avformat": "4518fd59f338448ce5d344762923e7e0e11fa1f845b154c87b0c5c8220cbdd30",
    "Avutil": "03b98eeef91ab9d616935c6b9168af250a433c6421b099c9474e8c855e4050db",
    "Dav1d": "eb9590498141f9b09dc7c2e69cc432f53b390cf4e007aa89c80bba43d052bf9e",
    "Freetype": "b550ab0fa58cd997a12e69a6a34228cd73f41e61de2ed162869ace60be303978",
    "Fribidi": "136dfe2a6b8c21531bfc2c49b8e79ca7c6b55d6e4ce8d899aa176d672b0cfcfb",
    "Harfbuzz": "5f14d941aeb54a952a087d151514f61a47d27616285ca1b96e8f2ea2a15e0827",
    "Mbedcrypto": "7b56d894335dbf3223b2be04dd33fb413130dfe3207c86a7c9ac9062cb676899",
    "Mbedtls": "eb4efdb50a60a2c2c618ac49a85f2b865afd1a2d940d87e90a1aa5cb28536457",
    "Mbedx509": "54c60569981b34647effc2e8e8be6e6c732e084a1ee1fb1ed6d1eb46e527891b",
    "Mpv": "b97c086aa738325ba93fd971de791ead656e2fe0da10c77f595c77af083057cb",
    "Png16": "3b6e8066650885bd169ec127d374223de5288605d35d51efaae8b4a236e15b27",
    "Swresample": "844d358eeeeee30e846baa4adab5f60205a85454b69f20724339a7f0fe7ffb7c",
    "Swscale": "7f7ea81634b0bac9363f50f97e3fe922a9347e35e1517677b0e230dcbec61449",
    "Uchardet": "594935383204e75b934c1d067924770c396ba7f8692032e884753a8a2a956345",
    "Xml2": "ce418a50ee3443db7dfc7d9b00c6a4a4f90495235df6456d01ad54180cd92650"
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
