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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.19.5/libmpv-xcframeworks_v2.19.5_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "a57a855adcd97aa0d4ac5fea94647647e5cb9dc8e867a319c15107adc9c81c80",
    "Avfilter": "4b7c88ae4b4dd63779979100251257cfbb8fd784bafbe76fae2294398cb9688a",
    "Avformat": "4bb6c74e4c88469ff42ca62447d03fa9d86aa6e49b28cabc71b803e919057ec1",
    "Avutil": "54ed140f1811e7553bad27108646b2542de3369bb01faaaa300fe973afd8ddd4",
    "Mbedcrypto": "0eb02bd12afc76a36e4b436adf9d15599dbdc1c2564cd974d6addff4e84d31c6",
    "Mbedtls": "a64790812e9d270ad50387ce843f767513d8430cfb0f12f3c9695db31f875e33",
    "Mbedx509": "3054440193180c04b08870972a462a17f37f5b9bf5772c9594cf5458fc7b31fc",
    "Mpv": "7b4bd921ac9d5af41c5df1491975b5723f0e1868c250b8f66c00b27906b55e48",
    "Swresample": "51c4db120c31f8e2cdd17344e79d8221a79443539f2c3084fba9fe36dd4dcdf1",
    "Swscale": "1751efd6bb952a82a72e70813f352151db9bcf5e52d148b999a10f89e184227e"
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
