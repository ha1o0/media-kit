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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.9/libmpv-xcframeworks_v2.24.9_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "094e4271caf98a9ea4c444ac15b104aa20ee57ec092351b26b83d97d7d7ee9c5",
    "Avcodec": "4ff6e87eaf84d4bf9fdece55ed79e1479924c3f4515810b6bc2bb78e682d1c22",
    "Avfilter": "5339f5979f1cd09069667193355bb6135bab7b9c94fb977cf9c952b299a9705d",
    "Avformat": "5c0d5a0be80f7ee544392d990a73b84aa55d02f3f89d933933b03e83f67f474a",
    "Avutil": "3c90674d6f552f5e71640956a17be52230705638b2ac6381bf6241c49a510c04",
    "Dav1d": "a7136da52c18f069cbe41811d56bdf479c693ce20ec502a6db552785c864ccfb",
    "Freetype": "323bf4a251067624698a82c0a3091e971af30de7c7609f917f5f58867406f69e",
    "Fribidi": "78d34216c57ea67489972493df4e4d5336f5a110ffc70baad375ae879160d061",
    "Harfbuzz": "ece44832d43b53cdad7173c41c0bac9696ae2361ccab32865da958c11f438910",
    "Mbedcrypto": "97f23d31657b2fd9a6a5f509a3f7a4a028701a5272f944c0489425d9fd5adbda",
    "Mbedtls": "e3ee0ff591776449e4fd93f8a45c266a01d9cbf27525f9acd31a1577f5d57314",
    "Mbedx509": "2cfd2036df5b0943dd56ebd81621431deab6753c323092278a325a7bdd010b1b",
    "Mpv": "5bc84faa04fa5d3d2be3291afdce97ee98d94467525254c98259469e3feb8530",
    "Png16": "5b5a319046c902eb581c29fda081370cdc578596f018dbfd03be0f95f0d6eca3",
    "Swresample": "0212025aa0d1ead80489474179bb8dc59b4a56ef7bac79ad715bab3933f4781c",
    "Swscale": "97a8d69fd196ebd48a1fe1313ea736f89e1bffaa938eba11e26cfbeee4b699f1",
    "Uchardet": "69ec7042a9bc22f5ad10dd8741819100c201bb0daa1ddbcc400e52148c5eb32e",
    "Xml2": "38d594324be4a0bd162d9f735f3d30b1ae10a8bf476c4960af61d37d2970dafa"
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
