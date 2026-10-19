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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.22.2/libmpv-xcframeworks_v2.22.2_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "65828694d07f74a19e29914db33af10ba8f8e488076cbb874515ef3382e6f752",
    "Avfilter": "f4e026f7fd9f7f7768a4b48db7345757dd114d53132ba5c6948ee82c3ac7d2e4",
    "Avformat": "e0dc21734cb95db489a8dfb645b8b57df50feeb340484af06531139637c4a247",
    "Avutil": "bb36d44477ee33f43af6eed822c06d628695c5584a7e52400b1b521e95ffb5fd",
    "Mbedcrypto": "b89cd285403f637617ee288be311e2b2652a63515a5cbe76fb146777da8fec67",
    "Mbedtls": "740fe18fe330ff33918333a34d7f052d404a61538ecc119a43b5e0859846bfc2",
    "Mbedx509": "bfe37a8d72e7b0417b72842bf253365a9b648f4dfd72095665f1a02a0bf7710e",
    "Mpv": "2a579ae873ebf74f4aca146ec96919c34aa87006e41117c58e694f7d265b48e4",
    "Swresample": "05ad0fe4d4eb5ad80c2b1d087b5519d77ddb4ba02b88db25d8268b3e1cd02261",
    "Swscale": "b215e29f30d473a4386649c96e55a1f98e4e4bb9ba20c27d24e6c8e765489366"
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
