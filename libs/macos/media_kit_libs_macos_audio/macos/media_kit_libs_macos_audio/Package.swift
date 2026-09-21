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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.21.0/libmpv-xcframeworks_v2.21.0_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "2ae0d371e79f5a2da053f4fbe7e84146b68714e66d4b03fc2faba0bc0cef434e",
    "Avfilter": "91c0ee969522db7b4d6a417fbeac986c2d4da89937a1242db053e8bc52b41a24",
    "Avformat": "51536d2834460ce2fd7f7e6057476768dc301bc2949ba3235feb86ffcf99e52e",
    "Avutil": "5bd9d1ebc2c0936fb697d5fed6f6eb4dac42bd9082d558994e8051418451f754",
    "Mbedcrypto": "dc025d309e91af1e90d78953092d29a82f201d142cb1935d92f656cc7ee515b8",
    "Mbedtls": "0c8915aa8cd138d9e9d7ea31b6b34d65f94bf8a6823dea0fad66478fc9dc26fe",
    "Mbedx509": "91a5a0a4c807dc7dd7f305df72c8c77027f3c144dbd2e222b6451adf3ee5958f",
    "Mpv": "5b5736f2bf7e7f731235c7a7086d899435ea921baa3c23f55a9124fc49d335b5",
    "Swresample": "0c7b2889a8f3610b91e15dc7301620b337ed85796e22d0c357234958ae392f70",
    "Swscale": "fc9fe21b8b549affb3a5b16a52b7f25daf7da2225f1a8e8ae313ad5584060879"
]

let package = Package(
    name: "media_kit_libs_macos_audio",
    platforms: [
        .macOS("10.9")
    ],
    products: [
        .library(name: "media-kit-libs-macos-audio", targets: ["media_kit_libs_macos_audio"] + libmpvTargets),
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
            name: "media_kit_libs_macos_audio",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
