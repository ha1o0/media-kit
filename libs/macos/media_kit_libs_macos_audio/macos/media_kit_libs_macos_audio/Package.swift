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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.26.1/libmpv-xcframeworks_v2.26.1_macos-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "56d4d92f3667b37fee97a3cfa608f4647d66ea8912127ca0856af8f8cf6a816e",
    "Avfilter": "219d6c06e68ae28d7bfaf53e1b2faa6a162030d7fd68d441b75f8e0e9a3afe8d",
    "Avformat": "c95dfdb26ca7678289de36472dda3617532e1e3798d5030784cfdfdcfd0c7417",
    "Avutil": "cbcaf4e000535b95481f57127d759282e993d0f7028bb5b30a0e57e358cdf8e8",
    "Mbedcrypto": "6c1531dfa6c025f1e6df702f2abc9b265c189ce42b119cd5a79d54a11a33708b",
    "Mbedtls": "122ef8a76d99230286d9feb535086a1948ffcceb9a5ea7e1c05cbb4e86b1e05e",
    "Mbedx509": "982570c5298f6a254b45f30362fa3e9678e99dea3908c1a0d813ea3eed9aee96",
    "Mpv": "f85cc48279031ebca99701df962d753662177e1bf7b7bfe20a98165906f8d246",
    "Swresample": "1d89100b7e85ff7880f38739c3e32ac0a84ea6138a5b5dcf2f79aa7e7575e796",
    "Swscale": "476402fd0178290ba4e62901bd7c14c5dabc21f54a331bf6f9b31ce140c82768"
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
