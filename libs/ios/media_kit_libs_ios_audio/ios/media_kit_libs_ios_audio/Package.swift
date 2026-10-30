// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let libmpvTargets = [
    "Avcodec",
    "Avfilter",
    "Avformat",
    "Avutil",
    "Mbedcrypto",
    "Mbedtls",
    "Mbedx509",
    "Mpv",
    "Swresample",
    "Swscale"
]

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.5/libmpv-xcframeworks_v2.24.5_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "188d05d89b9331fe68d8000f3615ef8412e0201b9e08a02406d1a5d93a18a45c",
    "Avfilter": "93ccb4b35fa465aca6f6e3195b2a9bd7c8e9d38a78489aa7ab32a44bde2c855b",
    "Avformat": "9982cd00148a6542391ac1cad397867c4d06535fdab64a6c853a07f27144be93",
    "Avutil": "905819637736817129e9e7e5024ca31942e4fc9077f6edf969983f5b9a1cf5b7",
    "Mbedcrypto": "8c929f7cbfadbe2b6ae482c3ba6a0e2d09bff3ef050192be94ede15055ce8e06",
    "Mbedtls": "51db7dff7c4adc59cf6baadf2db29bd962dc3f60ce9676970489207e12466c46",
    "Mbedx509": "ae6a8862bd5f4086fbdcdd642632e4d2ffddef9c405227b0ddc19636ccb5cfe8",
    "Mpv": "0eb4ba7cf348d0e47867675b07d33c12765c5222fb7761539271eb4e76749f40",
    "Swresample": "59df2a2bb70760b69cdde5ba679c03786201b96f171c75cc6e6298485ca6e9cd",
    "Swscale": "1c1df7812c07ff436860357589299836a375368eaf0bb152c45e576668f17168"
]

let package = Package(
    name: "media_kit_libs_ios_audio",
    platforms: [
        .iOS("9.0")
    ],
    products: [
        .library(name: "media-kit-libs-ios-audio", targets: ["media_kit_libs_ios_audio"] + libmpvTargets),
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
            name: "media_kit_libs_ios_audio",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
