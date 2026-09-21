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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.21.0/libmpv-xcframeworks_v2.21.0_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "957d87752e5faad88d68bda12a7aa6b68aefd41c374476896e267bb18ebbabd9",
    "Avcodec": "b9ef150298fa7f0b87eeb1dace18d01f54ebadad6ec00f718823cc1d0bf7e7bc",
    "Avfilter": "c1e64ecfcae6cd820982c86546ebe3bef742096432e1b44af97a847362e27ba1",
    "Avformat": "83885d504dd45cdc04f0ac76f2a6d8b871d81bb0e448bc69759fbe7b0ffe5daa",
    "Avutil": "295b680e54c40939b1132ac15d2aa67ea1acec1d87b38e734e8e93d59f7f10d6",
    "Dav1d": "3add4a86687afe47b291aadead9788d6d5a36199b64798a6e19b5450bb28c4e8",
    "Freetype": "966e8b2dfff8ff32869d6bd625679a122f5b3145c41d807349d954f0670a2714",
    "Fribidi": "1507d001067d82196a42e5b0bd29694ed3f873fbf32f7f7ec554d8aee5e84867",
    "Harfbuzz": "0e2cf0022d2c345d292a3d5cbd270744b82a8e2463f9f276f145dda7965d276e",
    "Mbedcrypto": "aaa35a5c6229ce9830c5753272d339a44b99dcfa622aa4b1fd73d8afc2e94dbc",
    "Mbedtls": "68e4fab08f6c542d64bb193e2cf93ffa5b3863d437f54c0c09255f63ba6b4748",
    "Mbedx509": "26700d949f217f1b276edf1ed780070e18b5747487059cadb4a7b6e74111543d",
    "Mpv": "ba18f3379ce585ed405cfa71cd5a4b1b247cd2c7adb2b75d79e75d5cb42badc7",
    "Png16": "6e3e21068eeb997eb78bb79a98903ac7df8a4aed694573e5f3316d2157e9e604",
    "Swresample": "394bff0743f874f711ba3f29fc44638324aebd108d0e139b2adca53f31a54545",
    "Swscale": "1557d2eb8e29a24fd9ede8d50e91df3f33085fdc1fa32b563be79a175f945f66",
    "Uchardet": "85b3698c3ce0074c74f170844404e95fd59d3d018f6e3ac9fc51249a1db4fd77",
    "Xml2": "674a848608e7423f20032cbb46ff10041c88a9fc2e7f2ca12f9f0d4cfbd9b720"
]
let libmpvProductTargets: [String] = ["media_kit_libs_macos_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_macos_video",
    platforms: [
        .macOS("10.9")
    ],
    products: [
        .library(name: "media-kit-libs-macos-video", targets: libmpvProductTargets),
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
            name: "media_kit_libs_macos_video",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
