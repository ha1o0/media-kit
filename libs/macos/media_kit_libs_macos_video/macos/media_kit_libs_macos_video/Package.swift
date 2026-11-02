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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.8/libmpv-xcframeworks_v2.24.8_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "e85dcc2d68f2ea45dd87adecbf6dc99c957ac5a25408dd09859dea7dbaf43368",
    "Avcodec": "f2f3f755c6f14b8b468ac1b644716a25f84037f6fd503f90bd19a83327e0c749",
    "Avfilter": "edda748e92525d728689fdf073ff851b99c2756a7c242aeb87119bfe90cd4dbf",
    "Avformat": "3db3b4ab6770cc3f53744bf285f749e76386a8153172ead25903da578a9572a2",
    "Avutil": "5adb51ea6ea78df0b3df07098f572b8e14ca64e82b2f255794fead0e4a6fd6ab",
    "Dav1d": "0883b8fd942692979750d964f531e1459dfc55bf4a848dbb1efcdfbc1106341c",
    "Freetype": "1b5b851c0c0c34ffcbbc306f50cc181b0e4c54782d4a33ffc9b15c256dbc1091",
    "Fribidi": "7c11e1e55e0a6750308152e3e11afe0ab1dbb15103b0ba916d1ce4e1ebfd24d2",
    "Harfbuzz": "c6f627c62bc9dc2f689e8329a6045f14364d4e0cd24dad88ff6044be98c3a8f9",
    "Mbedcrypto": "eb2f24b4a45287cb63bdaeafd3873d6045256f6a43a4fe532d94256d412550c7",
    "Mbedtls": "0f5d98d50de62b8460d480d40248d1f9a923d98a1b5dd50b3687d2b3bac77d2e",
    "Mbedx509": "e325f49a223db5d88ee94743ca6a70d01d07ecc279919cca1e862989b37db042",
    "Mpv": "0cd8c5a87dc42fbca81e781a1563e2750945c2150f465da164974961ba3f8f80",
    "Png16": "c8c30be69558819b77e13aa84cc75d2ce86cc4f2155267745d2198d4dac41147",
    "Swresample": "30947cd2664e2cd043e47814fb75a95c30e0ddd50103355830731805b8b5a1db",
    "Swscale": "98e5c5e40c18b765dc0a74a6554cd192d551bfef525a86e4726b2c9842861211",
    "Uchardet": "ed3ec00f9b105f758c2bd203adf62dc59c543a8a4c2947ef980b39ddfee38be7",
    "Xml2": "cc6fd2675575ca71cacccea086b73d2ff8ed64a3f31d7532e352370275d8580f"
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
