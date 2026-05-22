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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.2.0/libmpv-xcframeworks_v2.2.0_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "40d9b07e30d7a5a2f9b65c5e2b80476ef6ddc9847baacab009aa0ac29f749279",
    "Avcodec": "e84e0839d33540316a32116a0463d6308e2c81e354314a756fd7e062bc82d9a0",
    "Avfilter": "be671d97b8d859ae369663a399e2f0ca08b938545959d3266f49cb03ed1ccfdc",
    "Avformat": "fd6e4d85bfd231c2cc9d466d9bf4e115f9617eddb0de30c73493624f58710ebc",
    "Avutil": "fac3e4c2de3e602d1bde86f76a6f2ae4360ee03c8d57f1460b4a74ab818884ae",
    "Dav1d": "d5115d6d99d67d05cba07e790f5de3439e8325287171a6daf812d3a68de338ec",
    "Freetype": "c10d429a78f26b7ceea854965cd2eb699eb80da534a51d3efc3defdfe90f5e0d",
    "Fribidi": "2a4455ee8432cfb7206efbae1dd27ef50264b5b6190f071f221cec1a0eed9725",
    "Harfbuzz": "ed2676f9a119b6a43b2390bd160d757b07d13c9bd5a5d9883303a6d3602f4621",
    "Mbedcrypto": "6a55ffeedf78f6dda61bf85bd3cc86355062691ddad14e3a0b0a44a770f94eb7",
    "Mbedtls": "0c162aa4ffbff5ad6d464550fe3be1ee35a1aa29c359a4fafd863b287e99989d",
    "Mbedx509": "e631187d8e46e1058a86951573b0382d7fa0eb44fd57e2dec00a465394f0dc96",
    "Mpv": "66152f4aa73259269e1caf2b16940dc65faeec781d085ea010161aa0694177a4",
    "Png16": "2c9ed28017b95003c7c7a6ec285cec19b848da67fe2f3bf976af9def61fa5c99",
    "Swresample": "9ac3fd17a50f8c50c872f888739f537fafb7d3326076ba4191d0c0a308fc2ee5",
    "Swscale": "923d00059c798832abc24776e0c71ee49938e0ed7393a6ae6810976872f9e53d",
    "Uchardet": "2cc6164dfa989c0428ba1ab3a77e9dbe6dee40e4951ef563981f25479c311c3c",
    "Xml2": "536d86a9efc750cb09d7c727f49133acb09ae36d1fedaac2c2ff10effecab8e5"
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
