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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.21.0/libmpv-xcframeworks_v2.21.0_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "fbf6c75db59091ea2b8240b8a7c5f4c7b5731337dddf5a30b26af7a18c187e0a",
    "Avcodec": "3fa5f845ccf2b4d472d06761ae62272b36fa9a854f2122ccd93930d07ad1e09d",
    "Avfilter": "88c0b4445696ab5df6eb58196f25a9673962a7665ce19601eadd70175898b013",
    "Avformat": "89d0c18a3221a35691dc0c6dd6704ca0da8484e40ebb3b9df744602fdcbaac9f",
    "Avutil": "39224c5cc195878291d3c381b9aa125a3e99e2e5eaea5ea54cfcd97123629019",
    "Dav1d": "093df2ca390bc848a578d7c694dcfd40fcd4dc9667976a01399e9733052cdb17",
    "Freetype": "adc3b4e9573c28cb65cbe825d62aa1161c2e40dfd5828dd1967202ff05b9f33e",
    "Fribidi": "0201367c6a53f5a8979bae467d9f26008694ed7798341561b7eeacf45d8806bb",
    "Harfbuzz": "31121a0949fffeb03176229ccd5f043048e1ff8ba691df8ad47d6f34d1c39660",
    "Mbedcrypto": "57402a48533fa539658a85f6a1135c0fabca532eb4ab1a6b3483773be181bcb0",
    "Mbedtls": "73a07b6b4ca7cf5eb1bdf936df8a52dcccc7900a7daadfc821a45364bff99450",
    "Mbedx509": "1ed81ea82285fb240083f33502454e4cad2b87fbf5190936a12a7436c77dd170",
    "Mpv": "f6a186acc1d9bba49f9a24883e4fd44ba1e29cc4c39890f200c17014ae7cb2d5",
    "Png16": "49b09f0c4603a67c605fc1b363c24d4477bf05551e41782160f389202458cb52",
    "Swresample": "fea93dcb5a0648f38e39137a02dc246ab7d042b590ecaccde7c3bf249e3ba62b",
    "Swscale": "3f7e1d3fe50f66cd6010f2688dcfe2e8405acef1ceb5cddd08741d7c5cbf8875",
    "Uchardet": "b4b95e0da140395f728281f26dad5de82e5802a83aacfac0d6e6a7ee9ec968c6",
    "Xml2": "976c338dbcfe35e2ab67321a45ec5bc4ecb3c6d6d9e30938cd0ee097ea690648"
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
