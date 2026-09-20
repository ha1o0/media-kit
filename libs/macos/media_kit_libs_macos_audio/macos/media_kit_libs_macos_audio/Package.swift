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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.20.2/libmpv-xcframeworks_v2.20.2_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "fd02b971923578b2c86580f5e8ca120e393dec939e8a93326bd3b63900816a15",
    "Avfilter": "c567cadd770f77ef88122a216e786fdb0d1a87fd5fd601ff5fb8ce0dedfca0f9",
    "Avformat": "eb11bad64a80f2a69ed8904a041f08e7824a5b95b09a40f7576128442546177a",
    "Avutil": "272870a991440d7fbc1faed23592cbf5abbd210802b36713556cf5085387e359",
    "Mbedcrypto": "d1d9a3953b13697958f54b31525333e937cd970c566595233a4992fc70deaa2a",
    "Mbedtls": "28b992d9bce77f9b22391c1d87e9f992064960f97545b54e698875f9031a597d",
    "Mbedx509": "1ce53b25fbaabd1444c48fe07f958587654878d4d5385231a6d9ca66247485e6",
    "Mpv": "537ffde1b83883c8160d5be7ca4927d0bd3caac840dd1ebafc5eeda5a0ada319",
    "Swresample": "ccb3fbff61fe0ea7670e1dd118235d051148108397f0743e37a64f1d0ff2a95b",
    "Swscale": "eb8c56b9f23ea685dacf02a8dca93ffd619c5e68e002c4e2d5b77f65e17ef552"
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
