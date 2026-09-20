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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.20.2/libmpv-xcframeworks_v2.20.2_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "1ea38963f4f7d2970be0a48e75a32bb98e1cbd9ecfd8fd387d5c40b6a41095a8",
    "Avfilter": "e071cefb755b1b3529cf0655537e21129816ed83d9180b4cef9376643e28778e",
    "Avformat": "9ca2ede1b80ca60a8b5733563ae01d371f3155de46fffcd8f3d3b683ca1fb763",
    "Avutil": "7273446c1d9edf574dffdba0265c7f62a32ff9cf4fcc991ddb323aa4a2fb342d",
    "Mbedcrypto": "2451dc1290550def174ad296a040e361e8bc04477a2c57b688853c4b5421a350",
    "Mbedtls": "bfbabf870e3ff88ce3f793adb8ba660002c22699a98aa3b1f0698b6ab7e27b9e",
    "Mbedx509": "34fec1331ea02402384222552e6bdd2f3d0c961529cb64ed487a232a0b3ebe16",
    "Mpv": "b2230377889a336aca70a4d5eb294ddbb623e94dbbd185a5f050fba328363594",
    "Swresample": "1585bdd633a003a63ec0466f99f309a7e4804002c88f279a7f0fac8f06dd38df",
    "Swscale": "d085f4622615ddfecd521ff56b87a37a3b106ae5034b0a7eedf7f4dc95529caf"
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
