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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.10/libmpv-xcframeworks_v2.27.0-ios.10_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "c2eb806845681d477f6ae444a95ec38eb84e963474e38f43033d11c3514af69d",
    "Avcodec": "fe6665738114c77f8258e2df248808a35e3f91ad758f86839da283c266e33d47",
    "Avfilter": "1d0fb229fb4e1dcf7822c8ae9f258c2f7e517c8208e22abb03800b7a6ffee2a7",
    "Avformat": "42739a277a5b22465fe681d8732bbf3a133713f763fd5be3f9acb6f8524a4b09",
    "Avutil": "71d452f01c2fb24558d6719678fefe3e1d58aba1ddae72f4d4553da4a7815439",
    "Dav1d": "7f53f0983e52b73c40c4263d1b41f79cf5638ab0f8baf788e511fbfa64445b27",
    "Freetype": "ff83c8ee4be97575e8dba83d51f50800b8b65c07c094c1734593c7fce9dafee7",
    "Fribidi": "c9e6293c6cc8489f63309edb326e49dc4158bb9203b8f592afb70b281bc48eaa",
    "Harfbuzz": "13502f2a49717c3e7dfb9904e16a0c6a8c3f9a04ee80becd87f87e718e6878ee",
    "Mbedcrypto": "3515f1fb6739b4b29ead64b511307451698e3688a17e1e5ca6cfb9d57d44484d",
    "Mbedtls": "48dfd3804d5afeedaa836763fc96576f45f3490dd3a0af6c31a0527c2dc0d9d2",
    "Mbedx509": "020fd957c954a0e55b56890268b9fb00260873bd3f6520413939be4a698c653e",
    "Mpv": "9ffbd2f6aa2db05594aea48b0bb7b0ba3189a673d5f75175769fc4dc81e45683",
    "Png16": "0101b4d95315eb4f6d9ca46ad662090cad711c8b131edce7528d967e17ee82a1",
    "Swresample": "339f9c256eb7c257ad8ec85c19437a28a20dc9ea5ffe570804e9a0a649ad978c",
    "Swscale": "a56a6531f740db9c759dc746f1967723d2b8f4f1ab5a4e2d9cd9935d988b4cdb",
    "Uchardet": "08642a39b3900501e1387221b79f4ccc0eddc29c41707390a0eea939b4a5d120",
    "Xml2": "5cbb9faa14ee897557b40127125cc74fa461c47b529d56f56e6f64c5be5f26da"
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
