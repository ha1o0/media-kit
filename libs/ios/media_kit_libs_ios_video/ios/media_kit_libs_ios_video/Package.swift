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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.6/libmpv-xcframeworks_v2.27.0-ios.6_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "08494671e3787ad11740b2247ebbb1b382a5c09c81d7b3146d4fc3ce1458f900",
    "Avcodec": "1dfc56cbc7aaf9dae045239bb907e570d6901e1741619ef810a5286549f92dee",
    "Avfilter": "7798fd7ad661c9b11bd36058948c44f74b35c5132bbfe96995bf5ca660a54dbd",
    "Avformat": "d66a0e7315c6e2b6c49526ba0c43b93830615274c09439fc34b5e3edd58ff096",
    "Avutil": "aacc2464ae4202a1cd9d60bf571ec2c0c0f7451af1ba3c164439ebceaf702ddc",
    "Dav1d": "63f0e26a39323ed1c3689131ff16fd4eb4f287646d1b5c7d4b8432b5d2ebfdea",
    "Freetype": "f124fcbb051e818e66b7d687353b92853a2300ab79cdef62fa98cec865c9b6e2",
    "Fribidi": "cdbbc72ce0275ab8ea079f8793dcd273c7fc7432344f8216ca6fc1370afc7bf7",
    "Harfbuzz": "4600ef4025a595d3c68784a869043fb10e852dc83f674c9896ce44046fd6c88e",
    "Mbedcrypto": "85054e6db448feedbbb5cd55954a2badf786de2ae1dcf5be1d6e71e565156176",
    "Mbedtls": "4f04c6aac69f9c2966784ead17658a2d431f19632af11fe29d83ddd80a5ca01d",
    "Mbedx509": "b82ffdc7f05317f5b604263075eb961652c8b13469129908263a5690729b45cd",
    "Mpv": "2828c070e354c2110f38375536d1368bc36546ba486a9f33201c69f9841f83f4",
    "Png16": "71cb0f06a856a35bff1023106a8714b95c109da84f854c942d4f4219b07aa600",
    "Swresample": "5be6883f6a1f44995e7270a0eb8f89004c08a2c6370156b8bdb724181d5d6edc",
    "Swscale": "e397f8ee9091d78d2c1e9f7ddf800aadefaa0a378010e30fdfcd50f4c48e26b1",
    "Uchardet": "d62ab6af8e7f19f06b3fc4569ed82930ec65276b38282dd1b28cd47d359f2c95",
    "Xml2": "aa82eeff250dfc4b5735cf0b4642cc969f14eb7d6de16f1b85590884bf7de128"
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
