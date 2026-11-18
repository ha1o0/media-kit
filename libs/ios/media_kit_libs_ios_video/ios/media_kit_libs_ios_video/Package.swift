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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.1/libmpv-xcframeworks_v2.27.0-ios.1_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "307c5d0a54fe6602527f7a5ae4a70fa48fee8f32fe24abef5ffc9dadc3678812",
    "Avcodec": "8b727aacb8e017895a3d8c129f1c9c0e351e3381bcf6e0d21f30c71ccd34caca",
    "Avfilter": "5b17e8f6c66a6c310655828985c7c82fc2b39e1e9fb5fd8b5acca52aa8a11fa4",
    "Avformat": "29bc784d2028a7690ae5618a8aa5679975097e61d5586ec3ab48b84d5b68f3eb",
    "Avutil": "26a854d15acf7f343b23e9c0f239d16ce913f0d8bdcf9893592cdffe90762931",
    "Dav1d": "6e564fad029e843f5d51043b84c929b97735b52c7b98f06b507fc0fbc91bb7af",
    "Freetype": "1ee407685ca5e5235592909f22e95e139a1dd307e2c251c099b21b5f7a0eb2d3",
    "Fribidi": "7aa7d36dd0332ff11829f99ccc48c3e057fa3cf44c74f8b78ecbc0c94ae62c42",
    "Harfbuzz": "5a5d89f2d0593b30fe6b71e3e6b6d05f895fa0c974e3229e1617eb56e21e49ff",
    "Mbedcrypto": "550e28300f0012df6a3a6b0308cb15feca5ec2aa0213361a6396850c1de52471",
    "Mbedtls": "ac212d5841f3507b79b9bed29c82da1f653d066410254347bf171db7361fcaa1",
    "Mbedx509": "b53d7b7fd3a0babdcfd0e892ecd2d89fac20c5fbe5c3d30a4c3315b46663a269",
    "Mpv": "38f5442873cc4656a0858317edf635bd4e522602d794486e3b2acf9aa703aebd",
    "Png16": "cda1f7f02ff9d3dbd72d91c3655c65cd6f2facd6af933d0191f96ad2323ec722",
    "Swresample": "1fb3a91e0179017badfbe3fb2a05f846ae92cd93bce61e2890d5691db7835c74",
    "Swscale": "beba9542e8da562c9194ecefeb7098af514c6dda54d26ae8ab7bd49683c19305",
    "Uchardet": "1cf69b55d1e449bbfaf243e668b2178a3218ccea5ceef05748bd4b1ee4f0c797",
    "Xml2": "f62cb84fb2057a801202013b9cfd4b5854ea9e68a2b090964bd395380fd1097c"
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
