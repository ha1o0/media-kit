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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.5/libmpv-xcframeworks_v2.24.5_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "e26f05e74b32293176a8bacdc9b15b1b6e02165b8ba6e0f838685ac1068b4311",
    "Avcodec": "2a14dd274136595bbd9940c6e0467d68e44a4047476516341bfbe43083ed8ee3",
    "Avfilter": "ca09b4bfa65d11b81d20a8b0f14b6710805e54302bdcc96983e4cad31605df14",
    "Avformat": "43c1c8787c4e2a27b1017b74454c4217c9c7ae6642443f42cba353d48e3563a2",
    "Avutil": "a53814141025cdc31b69231822df04a0894b093a57395c0368d5ce6ef2cefe32",
    "Dav1d": "d32eca1d3006b42282ac2417a33900951820ee1ffedd8cd094e249bbd2fb7333",
    "Freetype": "0d316490b9098bd4f3f540f5b9c7bf90417b1145e11f4475557c11afa98c01b2",
    "Fribidi": "be1d45d4c2fe77953072306a4f70081d5377dd90c4dca6790ae728314eb50057",
    "Harfbuzz": "acaaca36f4ba6284ae0a2076b564404f193bb5c365721208fdca3d714fcb0a74",
    "Mbedcrypto": "0e039789f6169934f404b06296a1c6f1af837f1ee520399ccd36145212102dff",
    "Mbedtls": "09c36fd4f2ee175cbd19b15d2b14dc728cbfbb33dd7140f591c6c4da9c7cfe76",
    "Mbedx509": "68bf5f60c26519ec83a15f669c89bb7b4e7a76d17d9ee9c634408559be5b9bd1",
    "Mpv": "ee86a4f3bc803ca34b1a857da52c8a1835eb606c07b04c485fc906314b677b16",
    "Png16": "c0f245eeb57186d98579f2ba71383b5cac31137b1439c929a6f0b951d80e4e8c",
    "Swresample": "fedee1539612b6ca90a198a50bd4493f2ee4a25df6f2ff9032d5450c557b9238",
    "Swscale": "5fe86553707aa23eddd1f9dd297ee997e9af1e5c57fde15936232d66eef3cc30",
    "Uchardet": "0a4de504b49a699ad944728cbbee51e7a14d3338573c5d2d77d4603f691880bf",
    "Xml2": "3ce07be7ce1a0b8d49d5f9ef00b98ae953604d5621a9306195582def46a3aabc"
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
