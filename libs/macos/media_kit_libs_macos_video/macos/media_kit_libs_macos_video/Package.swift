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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.25.0/libmpv-xcframeworks_v2.25.0_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "fc5daaa138039a4dcfcd127352b6ce8ae7f90d82cb4d91de1760bf300ee915e2",
    "Avcodec": "aff82f7e7c72482cafce726c41a0fe95f4851ae8da27dc8e830875e242e7aa39",
    "Avfilter": "0aeb5c23eab5b0ccfa19ca4882756e89c3a94505da064004286affd8f10cf40a",
    "Avformat": "9f968016bd665da3f7f8723e2f6325681e10012357838a66b5f33a20cda25eb5",
    "Avutil": "43465112fd086419b9fc8539c805813a8f8e6aa92ef78470683aa3c2221dc00f",
    "Dav1d": "2842f3fdc64c639fcc4ce6f8b8f1c556b8f2e4f708d232b5b27040e1c627ef7c",
    "Freetype": "a30a3990c183cfca748f41fc1f6411a9722a5d36fb3a4a0593e023c5a43b4d94",
    "Fribidi": "b6a2c5ecd4a7ec306bdef63285a113f5d5a04e5352ec44ccd9a6d88a3ef4927e",
    "Harfbuzz": "6bd23d1c5ea7b40da51c47a991b19fdcd380638fa0f7724fd158123ba6c02ed0",
    "Mbedcrypto": "ec90f6d042ff617977e60ca4b888f8ea295211b241e1c01c5e80ca367290161a",
    "Mbedtls": "d33920aa3346744736f3e4abc3a1e0d500676b9b62b3cab5d518a1abea2e3ba8",
    "Mbedx509": "a107edfa25c8573dfe4fb2e287b66e34c39281efc923072b8596d4bfb8c88fbb",
    "Mpv": "15235c5869035d866648f1d4b56b440ca1f9155485db33efd2145b5b5cd7d94d",
    "Png16": "07ffec49feb1c0c5cf6448d43a6653045fbb0e7b8969d1c10f26c94ad3736afd",
    "Swresample": "3b4ce4241a902fd4cf8b4353779ec46689b39feada069f1affbde23cab73b841",
    "Swscale": "d725bb01613c8ad9db2be1406d6644ab9a392f3685863eb41dcea5c182596fcb",
    "Uchardet": "01473134f17b14c209886a11616d4dcb020a8c618f3e819bb747e7ca62121dfb",
    "Xml2": "899da0474e9acdb37458867a81911540187391d5e67409efb01ec4d5a67b5f6d"
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
