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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.26.1/libmpv-xcframeworks_v2.26.1_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "1d0ee6caf07243872754911faf6e2a0f135cd647415838364d421b8aabd801e0",
    "Avcodec": "06e554dec9008f49809e47e9afde991c5d09b16cde86691abd43e0057e32a618",
    "Avfilter": "4ee35784a9dda0ca62655ec47f73c7faad8bf13d4add46777b4ddc29f22052bb",
    "Avformat": "3b1a9480da1c221b7640228160d966c4739669dd3ed7e73e55258d036e578e37",
    "Avutil": "dbda468dc1e68314bc5322d4f81b09b3d6aa3ac7b73baa22c13c3ee8be019384",
    "Dav1d": "18538bcf92929cbdd76c13429494e64ad2a430380a23499956e06c76bb327b9a",
    "Freetype": "e206e25c75abc7a7b7bec7cf7d4940a88245a287faf635c8f0d420ce3668d2b1",
    "Fribidi": "21cae4b7360c8b6862209cfded24d94f6ec8c86f26f0cee4770499a8be5470ae",
    "Harfbuzz": "8a6f49a950e61ea4cf5d8812772e8008325835f05e4011a6f18a51bd095d44f0",
    "Mbedcrypto": "5388bcf19fcddcecc1fc95f74dedb9da0c8032379a037cf50131800bae52babd",
    "Mbedtls": "8cac2320c0e398bb72ae08bbcd3d51aba7c0fa46279c7224d6dc73017034920e",
    "Mbedx509": "cd796ef734abf33d501bdda6cb5b2896a6965a1a3a58c36b6dcdbe4d75ad8245",
    "Mpv": "007bc8c2912f01863e8f40ffd28a69da7c1e205b5fa7c6446fb661389bf413bc",
    "Png16": "f0d75ba5fed81a8d033100a6f7c692217d79c38b1f55a4bd2a07a7448cd4d502",
    "Swresample": "b7b32efcf8995ff7f6d03adcc67c00f7f11ce8eb15b62c6691093bc1a4dae9ee",
    "Swscale": "bde4f0983a6b6ca51663cea5390284c12ae8a55587dbddf728d2f81ae636c473",
    "Uchardet": "c2661205e2cd0e8df5a0de87d02338f0a67cbbf7252427a5a13e0b96e41572f8",
    "Xml2": "2b6841ec5a1901073fad22efd468d07f2f572c7158cc9c5ce2e721c7ed767a9e"
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
