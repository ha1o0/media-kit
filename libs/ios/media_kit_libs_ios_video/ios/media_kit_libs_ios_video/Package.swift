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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.22.2/libmpv-xcframeworks_v2.22.2_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "9cda5661e34239fa4ba9516b8bafc99015ee3a4aed46e71e851f09197e5b7961",
    "Avcodec": "d0c63c51a93818e1e5ce652569ed2b7da3f958e43511e4ce2b5f268be5165ded",
    "Avfilter": "0ca5864e24aca597b5dcd6fac2940d68944b5dca773ecfba23c9b2d6dcd2dd1b",
    "Avformat": "f69c843deefed045d388cddfe6aeea15a9ef291ebb5db236e78b1bd4e046e737",
    "Avutil": "9f72aacb2a125add3a7b46ae382a2210f3614d38441ef346a6433106aee9bac9",
    "Dav1d": "00cf14019719d305210ce81505b12cc8666e8a9bd2bf0b83373d8718fe4eda32",
    "Freetype": "c32a989a5ff601da8bf597e6a2c738d9b8927bde731b004e7cbcc91f134a747e",
    "Fribidi": "dcb4b5e24d3c501a8bff97559ad76c30f6085a26f72ba4fb8c36e9572c7bfd15",
    "Harfbuzz": "f802aaa9c8bade8f85075e92301ea05eeae8afcb29394df0ad47172262db0ada",
    "Mbedcrypto": "ef73bede0e8a154ad9f210242a6382deb913359e0b9181813a645ee7f38a1e0c",
    "Mbedtls": "684b46a60847b66b773658150d086d66a8e4400b6d2b02bf01c6df6d5780506f",
    "Mbedx509": "7b2b28135da705233a19a8f41cb2453751e8615416a552723bded7f2cb4ef293",
    "Mpv": "513fb913b0745054e582dee07565e63b72a6c715d61db9ab22796c78bfa378eb",
    "Png16": "2311f9832654b06f04cb6a3bbc00b0542ed0f8763a86be87e65cc48acf8ae7cd",
    "Swresample": "ee618c3c77db5787c76d8d54c70763e9b35cdd7da8b394d7bc387d57e8771564",
    "Swscale": "55e962a3a95f253a8f633724c422a8f50a0cb82e99c1d9978540463aaf804705",
    "Uchardet": "496e5f9d4e2b98a09e8433b76af96a48f42cf8145121ee23fe7197946e84d3ec",
    "Xml2": "0a57f2f2ebae43c4ce76d1f16170db59c50cf25eec34646006afa96d56c2f70b"
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
