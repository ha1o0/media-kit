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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.23.1/libmpv-xcframeworks_v2.23.1_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "5bdda43fc6002de49ffa84827bd4c5aba087f4781121cd7187a2e08ed7b7d9b9",
    "Avcodec": "3f0253d1c74e79bd65e6101c5081dd6d21177f9f2871d2738d6ba77a2d175811",
    "Avfilter": "e0f2fea8f22799b323a03e22f2e74bb84b887385b40add09b41d0fbea638100c",
    "Avformat": "d3b3cf63581b46128fbff98dee946ae87ef7db5822e3c6da9bc95ca62f7a46e9",
    "Avutil": "60367792604f463878f1711786bb53bc04ef32a509dee99270bca1e4cc996b29",
    "Dav1d": "dd5b2868a7560aca0f65fd63909607d5a4420a3be65c494d1db04012d41d2380",
    "Freetype": "073a1a8b5198ab26c19a7e012a6810d18975caf861438e13e812324911260eab",
    "Fribidi": "3e30162a754db2e5e9b8eac3205d82e5d0c1694cc73b834934770bb796483cd7",
    "Harfbuzz": "7448920c0e4abce54359ed563e637c734051c11240297af58db389aac63f2cf0",
    "Mbedcrypto": "0575befa0b6e196172373d8a9cf012a352182fe35c7ac7f914904d99b3a19c26",
    "Mbedtls": "fd1009f71d4a805fd92065a94b147211919e6d8f8452e4c7db509b374f2beb5f",
    "Mbedx509": "91aa28e2c78b70feac4c8acc661ac310aeae49a0af0233a6496dee8220a036ed",
    "Mpv": "a2a56c490247badb80b4ce54accc8e80a2d8a51e53d7343d1c6a0912486b869f",
    "Png16": "9c34ed9cf14a901bc27854786c174e9270fd61439eda93ad0d6417b1ebe80870",
    "Swresample": "3d34cae2a9ef583321c4ba832a3e68816487334305c1c763a37f2f092fc59a1d",
    "Swscale": "a8207d9b3ab80f8e4d01b87083465a69a3d2152d5a1bb474c650c62c938d317b",
    "Uchardet": "46736929fad6e1defbbfb4d27fcb00705dd2e3c916d68b54283fe0b447209f61",
    "Xml2": "f46c425157cd9b961540643c9778547e8e6617036083f2a5b892dc71742b4dc8"
]
let libmpvProductTargets: [String] = ["media_kit_libs_macos_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_macos_video",
    platforms: [
        .macOS("10.9")
    ],
    products: [
        .library(name: "media-kit-libs-macos-video", targets: libmpvProductTargets),
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
            name: "media_kit_libs_macos_video",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
