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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.19.5/libmpv-xcframeworks_v2.19.5_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "df03073dcd79f3d5d87001f7f973a8bb330bfef808d4e7382966685422251b34",
    "Avfilter": "4b42099da95e7004c33bfe073f20fcb68f248be7caf1c9d2b7b43abb9af071fd",
    "Avformat": "56e7e6900297f5444ebb74287ac10fd63f3550bb7692c073c62b14506b39439e",
    "Avutil": "562afbb43ac13f011680f0e30b66f3328457724c29396325de62425c1c45e75e",
    "Mbedcrypto": "293b6a95ae8fa5eb9b358589ca7cb1b77d579976aeef13cb9357e10f9d847e46",
    "Mbedtls": "56ea6649762f538286f54f0a477ebf694c2dd2b2b192dd3514121efbbc77b524",
    "Mbedx509": "a34173a315d0c24bd8e271ecafec11b145d14ecdc79423fd8b41d82443d2fb4f",
    "Mpv": "14ed9b03490ca4cd73668f2a76eff2b7b61d6be900b9ba8f9ca385f3e497c211",
    "Swresample": "49790387291698e802a1a239fc04ed5b4023131a30be17e4b48efb0cb9750f43",
    "Swscale": "cea584d3712ce2a7acb5bbf3cea092df9dced729ef7b849a6085d4f7e3bb6b87"
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
