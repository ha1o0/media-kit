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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.9/libmpv-xcframeworks_v2.24.9_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "8e61d1f97e291e0f41f8cad4faebd62734e17358afe6b77b21925b34f804bd8d",
    "Avfilter": "edb70a94e6549e22492c9cf7d9e6f8abf2e3e17591bf715c8125aa900a205159",
    "Avformat": "4e9a7f02612fccc5ec31e62a699df5e30fac61445104881a5a39a910cbc2bd14",
    "Avutil": "575f69eddeb1e766b6c34e8f684dae6f1554e16785bb02b4d034c92da61e0d14",
    "Mbedcrypto": "a7adfcd55126f0f760c404a7c3c0267d340718589254289c3e91583b35b7c083",
    "Mbedtls": "5236a096be87b8215ea22ca892158dc11443bb9249210dd695e35eac20d6ac14",
    "Mbedx509": "29450808adb98c6b4e84b2033fb9a5c404218b594ddc51c2e52cc63f816d01c5",
    "Mpv": "754d504e4938ab9fef0c484092cc3ddf649e33f6c42688e09d8ecb686e68eb90",
    "Swresample": "67c86a682df88bb143e2157262db44ba071a2aa478a5b25558d349f05eb6ea82",
    "Swscale": "51bd3d2fe60f26200b4d3fd9a54704503480950b786ab0b5ba02d2e3b448ab24"
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
