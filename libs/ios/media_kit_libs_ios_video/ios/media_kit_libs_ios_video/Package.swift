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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.20.2/libmpv-xcframeworks_v2.20.2_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "b866aade0cbc99ee974ba2121d09c48d705c0e345260dd73e16e2f56cc35cf5b",
    "Avcodec": "6bdea11256e1047070861023721a2d9914c5ede1aba5d9bdf05012eccd401884",
    "Avfilter": "697ca772c5e38f261db840d973c4614f61f85212072136f6f82763b5e2cc62f4",
    "Avformat": "f4a66a3198a563cde78d8f5b5fdc99abab2bcd9a3b9b32930c8b53e3896bd245",
    "Avutil": "1f7feeec4a3d8fe3ad0e7197eb3cd58c8213556f98370d07226482b1a76fabab",
    "Dav1d": "2ae2045b78e21eb829b7459f7afa42cf66c49fdc34f56ae7b99585ac108f5d82",
    "Freetype": "7fef38293f2a2f10e5ad5614c3881ea34c773418d83770f35a4290b4277aefe6",
    "Fribidi": "95d50416474d7b4bc3f655e1d2e6ba97ccb25e2d84310e87c96082b5276bd5f4",
    "Harfbuzz": "225ea60b338b5b714e863af984dce9d6980c6200e735309e7506f2b485d34881",
    "Mbedcrypto": "c6d579aa388e1dd323405e8b8d8f95ef76d20ee20c38a1ce637b8dc0d6d2316c",
    "Mbedtls": "3a205ee85b8fa82e69246b799d97ec21ab96cc74f2de972467710510d59a68bf",
    "Mbedx509": "d501dc714d2d032b979c954c8e3df1a82e52663f723bec2f17ab97d8a2f62efd",
    "Mpv": "c8af017c364165ccbeb9e0ab4f0d882db97c2fdf62ba5c343fa1eac6e5d076bd",
    "Png16": "0632730dc061afadc83b172ee4fee231eb47bd349cd1607159b161d6e881e390",
    "Swresample": "c53f553c19836a0562abfc0645301dc9be82b31fcffcbe3e89845a0414557d9d",
    "Swscale": "96d2206d1243afbe0ece3a8ce365981e91ad63c4087b36a2801c8cd19a28395e",
    "Uchardet": "83fc914d609bdfcc5709360cdd5ca032b4782b19778dea643060460b3bb890c7",
    "Xml2": "62df46d2a19fc868bff1607daa44ff715dfcc2989bef57ef8b7d698e431a64e6"
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
