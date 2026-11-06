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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.25.0/libmpv-xcframeworks_v2.25.0_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "08e926743a998e88009ac954f4ced52adf6c24d0daffeeaabd58d522da8a62fe",
    "Avcodec": "8f9fb8883e40536ef7d3e25eb981a69647740df8eaefe4ec8b6461a1646c1d75",
    "Avfilter": "d98e2623b4a65e3bfc7259e0fac10a3590b44427b2894cab98c8fa2f3f1d0089",
    "Avformat": "d71ebc0154750c70b01fc8ae5573a196bf9675bfc3ba0436ed158a7f03d52934",
    "Avutil": "32e1a22803c0aa26434177a0188237e1ddb75699a1e89add0991b2ddd16e1316",
    "Dav1d": "8a5fa1207814ac3bee8eaf6d2a9458cd2361250d824d5a2528a2916a248a5514",
    "Freetype": "557daf648a53ebcd1651e6050cde7dfc08b860c1cfeb5dd7e01c8d1a2acb6a8c",
    "Fribidi": "ecf1728bba006db40df91abcb64642dfb80c4c1722eb327573659e5ba6148613",
    "Harfbuzz": "f3f94e6e40badf589c8e54f1c028ef2f300a476663e612386b1b05117233101f",
    "Mbedcrypto": "a348c20c923ec362a49136e02fa3d8d38bf853b8264d45d25ac3f018021ad1a3",
    "Mbedtls": "0a22be1e7b64f94b509653927944f50047a411c6ce03f1c0482f0bdcbe282bd2",
    "Mbedx509": "fecef43bf669a16912e619dd1ab8ad5eb9b3556ee16505e3534d236cbc4dd367",
    "Mpv": "885d2182107680266d4895bf87a925d4511aa49b1bc5882d58f7945af0e1c13f",
    "Png16": "c03c0de536e9813841380a676e5e806402420e4c22a3174d605aff125c86fb2b",
    "Swresample": "741c9a85e6930b3801e74c76d7ee94584f67954d6714d37292496ca2abdc666b",
    "Swscale": "5f8dc932729b0dc3fc27c470a583d230879f1a36b27d6a1a9938b6cb660c8af8",
    "Uchardet": "1b37ff31247cd40d66d8212ea592564ae0b943bb6f64fe1fb13c79b12f6ff9ac",
    "Xml2": "6c5cbb5f515cd7ccf2224024fe4058d4b83b4aa3559b9f3ab848fedfc568d3a3"
]
let libmpvProductTargets: [String] = ["media_kit_libs_ios_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_ios_video",
    platforms: [
        .iOS("9.0")
    ],
    products: [
        .library(name: "media-kit-libs-ios-video", targets: libmpvProductTargets),
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
            name: "media_kit_libs_ios_video",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
