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
    "Dovi",
    "Freetype",
    "Fribidi",
    "Harfbuzz",
    "Lcms2",
    "Mbedcrypto",
    "Mbedtls",
    "Mbedx509",
    "Mpv",
    "Placebo",
    "Png16",
    "Shaderc_shared",
    "SPIRV-Tools-shared",
    "Swresample",
    "Swscale",
    "Uchardet",
    "Vulkan",
    "Xml2"
]

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.2.0/libmpv-xcframeworks_v2.2.0_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "e919b0c61f9d2b84961abc4ca6b12bb7189081e161d8656773c6a61a9a0d2eff",
    "Avcodec": "2689e5b4a27f9eb657761375ea23b88157b5d2a166dc7f2e4c00a2a45a99fe85",
    "Avfilter": "59c27429e82b72faa4e98a05998170b541cc3d4a02eb0c7a4641007eb1e2b6d9",
    "Avformat": "56de49408f8ed8b3153ed7ffa734935d055acd8dee5e511009333278b250a1ed",
    "Avutil": "c3f65e580247430245b9f68b04abfaa0effc929e83763d32c76933661050e023",
    "Dav1d": "0547d935f9b5d655dc6e4cd4660da81857ef445c36a83c27cb2ff7cb57ac6533",
    "Dovi": "1390f9239d1ea66cbea557d9f5206de63a041487d6ac73bccea2a1682342d3d9",
    "Freetype": "eac4c80aa762f081ad6312f1ed7da7d45fda4909f590fb10c59d0f38f4e01107",
    "Fribidi": "3c95c0e03b1392d4b854e9b0309f4a5a25b85c4ff05eb18071818b4c5257f47e",
    "Harfbuzz": "a8c3e9e9074bcefae24c81027c85c3a66368180d517acc9c9066fafc0045c4bd",
    "Lcms2": "55d6703ab8eeceb93cf2410be7123f4db910ee82517b8699be4d398b9f791ebf",
    "Mbedcrypto": "4e1bb5aeb50dccca099bc28169e82534d63cedd23495121bcbbb52bd9e4c9847",
    "Mbedtls": "f08eb817e3b9ca4eb3d37be266bf92863575257fc786820b3d89e0ea25fba97e",
    "Mbedx509": "41f6e2ce86545b68c3610b1affcc4ec00f46d560d2d8d7b7419c1029978bcb08",
    "Mpv": "da1f0759b86ed163f2c58a0a9c347f010f9cf32c9f41f6986cea00989a4ef82e",
    "Placebo": "6f5c77572f98a10b05114ecb9a7ef5ab021a8e863463a7b3240fb783f3ebbdc2",
    "Png16": "2fe841eeba39db5658fafab0d2ebff9835f533cde3c014af8c31a871c09b66b8",
    "Shaderc_shared": "36ce124a0e86ea6baeb0cd31e869d08cf8a7f53dadceef11a4efe24cfcc31deb",
    "SPIRV-Tools-shared": "4fd569f823434dd202bb1817969bde017fb9c689c9e2bd3231be36ca22d97ce3",
    "Swresample": "dba7e96cbc42de86597fbc8904354ee32a33b88a72cd6bb55eddd40b4585b6ec",
    "Swscale": "8f8854b88e909c916a18c0e044cd2e34eaed2ed5b0c12b7c1d4bd74d845ce8b1",
    "Uchardet": "13f700a9a5cf1ca3739f0676019191396da769d3c8b01d7abdb0d51a0273b5c2",
    "Vulkan": "570b54e4b2a8ddc1bcdca3cf56465646da45e192a8b9b541762d13375507c146",
    "Xml2": "046e5b2ccaf91693ba8a45166249e0b06c9922d0dcb8c5304921008ee14d7df7"
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
