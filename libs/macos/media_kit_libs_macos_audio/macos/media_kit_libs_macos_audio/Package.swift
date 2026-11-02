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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.8/libmpv-xcframeworks_v2.24.8_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "1a422f97fce8bd32b6c2aae725d5a1b68fdc8aa957c41e4a2f08bff60df61e25",
    "Avfilter": "6a0c1c7159a3d42bfd29513183c8246428468a9955b3a41635b2ffd46eac85a3",
    "Avformat": "bc4991a0c3a92b0502de421ecea1fd0d95a7ef7e8adf90ed3ad7209d916f1938",
    "Avutil": "018e91cf7ead08ead9fec0dd8707c141658e06f8a953fb860871b30fabb893d0",
    "Mbedcrypto": "b5cf8e0397c58dea70451ff8913023a8e0816140a7637e898dc624b947334b42",
    "Mbedtls": "561469f860a47ba39f8649197e392f9dac4f0f152c73569e2844ace998a5de24",
    "Mbedx509": "fbbae24e17b04f859c08376d8e9b47f2afe9e82ae8b823b1981385c58d70cc8c",
    "Mpv": "6dab89fb325d58bb946a442285ebc946f940c15cbea8cb84ac38dedb0b4d98b6",
    "Swresample": "5dc4009e59c35fb159c2e5d5611c9e1c0e3bb882fa830fc551978961322508b3",
    "Swscale": "27eddad4a93d87b63933114fa1f2ea63492338e7572827afcd335c842646944d"
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
