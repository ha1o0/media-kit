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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.25.0/libmpv-xcframeworks_v2.25.0_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "de406087ede3e31a63e816a8fd4d075847faa6602f119f6a2516b3af6926efb7",
    "Avfilter": "abdcb32bc84bd78f9ad12414c8099350321502936fd6fba8139e4e7f7894e891",
    "Avformat": "9e49c1a58715c060c1d84456eabd5512adeb378c117650677f972b1d3b4e4265",
    "Avutil": "4307ba0f8e069d202813e3533226d26fc49a7e66df74535fda82ce64c9d1c1bc",
    "Mbedcrypto": "c74644230b80336c10e282079f39772fd21caa0ba09105550fa5e9fde378c85a",
    "Mbedtls": "96989328e6275a6caec7d191e3f19e077db98c7f17fb87cc334889683b2f0d13",
    "Mbedx509": "a13f21e6ef6b5b12e96e02a2a05f6f9457972121840c84491c3a9d5da998cfe1",
    "Mpv": "eebd8f82625c0eb35efc2edaf657e09c7449ba5e8de3e9b478a0eeb6f342f1e9",
    "Swresample": "918006f93512c367c4c7b6c29faa154d94d8cf5c52bea3fb6f724754a0802faa",
    "Swscale": "1502d363b377a1283a3e8fbe1f1552e92276db2ee797d1181bd62f6c1ffb29f1"
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
