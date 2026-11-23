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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.7/libmpv-xcframeworks_v2.27.0-ios.7_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "a9435be612fc3482a572fefe4f3c95368edab30802b5baaeecc6acc19ddab449",
    "Avcodec": "e9b8c2b9774424b8fb147421108cd64d440792c1963c09860d11612c71adb985",
    "Avfilter": "46ee4a8ca4dcb8867d24ef67cad187968ac4ed9e47b4bfb6311c109fd267c428",
    "Avformat": "444280e98a11053f5e27838ec562e26ca5829fa3109ef72fcfaf5c8881b981e7",
    "Avutil": "f0a1b63a9a8e5cd0e7d533ae9ce281c7fa2ba82ada469f050d00f0c819042803",
    "Dav1d": "3ad85c537897d44bb3d121b2729113ccf95b7b476f0521ba27d27eed774da075",
    "Freetype": "22394f01ffcb866360ae35b3ff6eb24d7bdf83d858fa3331b33105a8bfb48cd8",
    "Fribidi": "fc1783daa065baaa4ae0776d2a3fa89c516fcabf679620d093259abb3884ed5f",
    "Harfbuzz": "80a72eaeeb7190ae90084418598386085a3292aa4f53590d0cad12fa96017183",
    "Mbedcrypto": "901c3c8c6fb8a0224890fae7f88f78d5a364c277baef9686e5ca1490976a01cb",
    "Mbedtls": "61cb9ba271ae404abe49f8c187bab49004687b28a42f9e2685d5154ceea88f9d",
    "Mbedx509": "cc130727a828545c9a44cb934426b5a70022aeaf119a9295ba6106c8f44d35c5",
    "Mpv": "88b6507a87307030b5e9fc73a20e41ef7f76e0e6f4144afbe3486782161d3ec9",
    "Png16": "417a15fc6c005eba072ff0c361bcd95a0c8c033f545a4a40b29ccfe53922c8a5",
    "Swresample": "e833ed76de1c118b7b5f472a7c4bef04bba5a0b42f89a5f01e346c3eaa2b90e8",
    "Swscale": "794243d1125ae74881024c7beb4719fa323c786f22551fdee168cf7975ff0b50",
    "Uchardet": "bbf0d6494e7e6c075cb5bb520137387581cb755db966f6a7dbfaf7be0c72ecad",
    "Xml2": "44c116c2d6f6ec0118b7d95ec93f18ea181724a1b8f573196748d1fa7a866b57"
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
