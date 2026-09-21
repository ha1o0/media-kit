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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.21.0/libmpv-xcframeworks_v2.21.0_ios-universal-audio-full"
let libmpvChecksums = [
    "Avcodec": "4e077977d2ba5a492c7ff269039e1fbc57ae76a95a1d2095ebc4a394c2fe4c6e",
    "Avfilter": "d44c0d374bbf8f986b36786475b4b9c963af708015c44b8d1c267ac13631c5fb",
    "Avformat": "71adf6dab41f84f479658baa5cafa23cbec3c701ec8af270e7a192948d2e2140",
    "Avutil": "72a4fb7da52e106179a03fffae6b21b710008c74de483d356d4430015b8244dd",
    "Mbedcrypto": "211cd3b7dbcd172c49fbc050c5eb46751305dbd714c0adbb7cd99e900e3011fd",
    "Mbedtls": "68e0671440446d7a1c6a98cbf9c45a11db4d35e0c55543347f3acf8178d0266c",
    "Mbedx509": "4f5cda04434b5bd09da64b85872afc0e33f4676dcefaee7441fbac27ad482a55",
    "Mpv": "66bf5ba25d573324b72122ca8e7599a35d103c4afa63918e2335447dc3223dd0",
    "Swresample": "0134289186cb9251f5c0a5527f6e8ad83c2b42b06b4b40a641f7445ba50c7f83",
    "Swscale": "6b12b5efcd51ef3d98498b3491a1e308112ddc0a1a3cead9a80dad883c567fd5"
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
