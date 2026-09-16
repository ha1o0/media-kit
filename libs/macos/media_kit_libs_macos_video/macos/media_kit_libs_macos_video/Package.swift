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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.19.5/libmpv-xcframeworks_v2.19.5_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "6ad1a8adf1d865d661f4ffce233b9a9de945c488dcb919c0c3ffc188feaecce6",
    "Avcodec": "717f766233a0f8ae911dbd2580c12d35ed2babd7ee1a22d0831dfc2defc906bf",
    "Avfilter": "3a360bf520add0488f2b3ec1bc42323fe1abad826c9d40f88efc0561e857c654",
    "Avformat": "410c1730e109730b40fa8a1bcf29ec322daf718684121f130ca74ef22a21694a",
    "Avutil": "f31f97f209e302fcb7d1fc5a6c1e355fde7b07a9b2307b6bfcbdd07c463c29f5",
    "Dav1d": "acbd8852014e31936fcca9b2424c7f63db413c5c064db9be47760f51c35fb2d3",
    "Freetype": "ea2889dd32e4391539811b332cce8e7dd6bb121d3b47ee38828a27075df25076",
    "Fribidi": "89a6955822799fa706004e7f46d485301e6852637e3256f5bec53083c15284da",
    "Harfbuzz": "a8b72c2a786badbfbf6ba72d527c370a5e9f6a9a6390114b26a879d7adff386b",
    "Mbedcrypto": "11e6ae864ba4a4140eb294c3790f29efa96d71d7dd3de231882ea2f105cf4827",
    "Mbedtls": "5a4c62e7897b1b9dcd04ab23cf6adb23f07aa91bf54d66adb7daa57820c77067",
    "Mbedx509": "ac06569f12bb7f38deda5587542d62b471605e9c7981fcd909a126c56801caba",
    "Mpv": "bdabf8737d8aadf5471afc24666865ce6b081b39b064a161cd7bc4d5f6aece98",
    "Png16": "7c2e9adfa66c5b9054a6517a854ea03f26fd85fea93147ff6fc67d9f1e3577bf",
    "Swresample": "5da77370070a158d4433706bfe75b6c109e7fdfb63bfe58cdeeb00f82f996079",
    "Swscale": "ba27eedf653ec481fb39624de02f58813be88b754225c88c5eb348be21dfb26a",
    "Uchardet": "cf9d03819f62af9c45decb0e853983b8188715180e734f50a23e6162576da971",
    "Xml2": "7781c1f264a74c2bdca78f8b1d621088b7dfcc279bca610fc6687bc35354b9fe"
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
