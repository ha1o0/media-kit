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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.2.0/libmpv-xcframeworks_v2.2.0_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "fae4924aea78573853a43e7d831525e31735ddefd8f3142ce811abcdf5d63ee5",
    "Avfilter": "92f85d4f0fdcc87b5e3600f08f0e4f165a263f02c4976bb6658e6991039859ff",
    "Avformat": "8129570e6e8e2a8d9a8c7edbb1bfe04f6237ad457f15b21dc313366bd679f424",
    "Avutil": "bf20d96048c2c6e346737d4ac0512b77606a1a117ee9e5752bab57202baad6fc",
    "Mbedcrypto": "59452f6c1bfefccf43d51a1f68d462c2c6ab7b6894b3ba69196cd1ab32b0a218",
    "Mbedtls": "17b6770839dcac98c7d71f4450444f6e074a42563cb00000f6ab9db19a26009f",
    "Mbedx509": "3ae6aa42f6a23300f7886dc130d0e7553c8c695a5801ea62ddb96f354a9db0fe",
    "Mpv": "2142ec6cde16d80733f2140338bd19e50dc93096bc7bd3569634557a4b1f571d",
    "Swresample": "32b3da0abc8add182865964fd9eea3f527778f4ac726f97b045bfc83596b51f1",
    "Swscale": "29e40442b1e9417478def2835972074562ccca183686ff1dcda304c591505e19"
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
