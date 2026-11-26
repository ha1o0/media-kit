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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.12/libmpv-xcframeworks_v2.27.0-ios.12_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "99d1b221841ad5e98ffe98e8bb8d532fa25da348687a5b0f47a2aae05e0834a4",
    "Avcodec": "8c9899998b933a7afaeaff4de3b766e485d1281b70524bec30273c2956b7a5c5",
    "Avfilter": "4cb443382df2f745a68e4427155920b81191de9fc2d96a95143298cdcd3a36b4",
    "Avformat": "54a8b869a5aed1e7a8b75f1ab3458973fbf4b45d98d80fd8f557d76b7a7c608c",
    "Avutil": "238ffdea9c99320bfcc2cb78c3e374b2fb44d70832195e7c80bb13dd80d86d5e",
    "Dav1d": "bf3c7d7c92fc658cc56292f6c5e316538065f60cfdf4fa4e00b84c4b08602628",
    "Freetype": "aedc8d4dac29b2293c91a3e8cf31c152f940b0164e7a561fc1e8f6003a8cdaf9",
    "Fribidi": "9f1aaa0fbc95f8ea515ec318d59836333c64d574b2611a829c9b1371fa813773",
    "Harfbuzz": "be59fc815f48c863c90722a71aaa9d911f18b9e84625bcefef8a55cb44376158",
    "Mbedcrypto": "ce7a4ad37d9b7386344fd7ab7a6a45b8f9d2b04cd89ee97f8a5bd1e31db77a28",
    "Mbedtls": "6b17cd7a708452db05f455a52131ee902c6f1c5341b9d2e2ba342b220ee2466a",
    "Mbedx509": "089fd7ae5ce0f086cb8dbcc31eb67e7ccf942e4886b7e82a2bae54b58ba0860c",
    "Mpv": "fdaedb71db40f98012f392139f6229c5717c04370e55a4db058bc163ba182c13",
    "Png16": "a1aba650cd42d355f69d50f5a866662003bb9f06012d861d84e3344ca678ff58",
    "Swresample": "0f3fee868ce40c2eaba527e290f35eef12c4b1c73dd055f6b605e1db9887e600",
    "Swscale": "c66e77eeb13909beb75b87537408f97f963aaa8838b0e75e14d0d029f32aa56b",
    "Uchardet": "a1a9d9cca527d94d741df5a67ec81e7c129d60f2582de2e68564afc9861cd38a",
    "Xml2": "e80563fd319ee9ba9427fff20a487983a70edacb6eff22410fab82755732d4fe"
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
