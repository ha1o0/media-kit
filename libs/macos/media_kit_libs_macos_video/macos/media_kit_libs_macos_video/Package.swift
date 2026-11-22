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
    "Glslang",
    "Glslang-default-resource-limits",
    "Harfbuzz",
    "Lcms2",
    "Mbedcrypto",
    "Mbedtls",
    "Mbedx509",
    "MoltenVK",
    "Mpv",
    "Placebo",
    "Png16",
    "SPIRV",
    "SPIRV-Tools-shared",
    "SPVRemapper",
    "Shaderc_shared",
    "Swresample",
    "Swscale",
    "Uchardet",
    "Vulkan",
    "Xml2"
]

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.26.2-macos.1/libmpv-xcframeworks_v2.26.2-macos.1_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "dfe4b6ff0dc245bcfadf72c1027037250d99fd02f66077149c87695b85f68888",
    "Avcodec": "424f6bdd18ff9700dcce04e3b7c66246922415595c9f410432edeb56e40b9a79",
    "Avfilter": "f9e9b3e9543588bd2f6f81a32eb88b0d333b44e72d0d52696bf52e64886813c5",
    "Avformat": "7fbcf1ed65602b66486c9842b2f73d70dac3b6189fb0d3cbe3d23ae8d2005848",
    "Avutil": "e971386ae1479a58bdfc5e0e11a45c1d1e73acb9c44db51fd54244e32a36e353",
    "Dav1d": "b198b09bd397e8f0ea3f3baf186fa6496f12d39ccfe6232063fd4ef63d702c2f",
    "Dovi": "a7c68ee7c51b195538ced29f1dfd280c8490d41e57784d69b4c20dda72c56131",
    "Freetype": "e5fb0a5dc39c12a03741086fcaffe19f1569c7de689b6e4cdfdc4a57fbe81554",
    "Fribidi": "f0ed52c82fd98e6ff94228e918fbeb53c95812a6b7713dece040e6ae51807c73",
    "Glslang": "0158cdbeba62299b8c30408e7ffff3a8265e1dc7993a7b776dd0f78b881d03bc",
    "Glslang-default-resource-limits": "fd99130b6a50eca50ddfda3c85c8c6f92b830d3944cbc992c9abc328fde2b015",
    "Harfbuzz": "7697462f8ae28495316eadc3e7a963bdbdf983d91ed4a97682e519540f36779a",
    "Lcms2": "a8f30c6b46b38fa114e0bbf594f22b23bc43168f92457c04b2341e2ebd1f3687",
    "Mbedcrypto": "dd40cd5d03de3b55876db867d83bc3c5c5ab9341699fa54e9d634b86875338a4",
    "Mbedtls": "a6e0453e4e872f6986565a42671ad287c14504939d2a3782ee3a3f2f2d119fa4",
    "Mbedx509": "54abadc7f4afc31f782d0473d293278b21d0e8ed610d5ccf4d0f5e2ca8db6887",
    "MoltenVK": "bde75cb3d88b8e5195a761b78c16796f2404faca88a3734a51b0ecd863dc28ab",
    "Mpv": "599f9057af0b07a8ff9c251bf8d5bd728ae8c4fad86b4eb9e021a9b52c2d09aa",
    "Placebo": "a3eea835006003ff8f72402468bc0c05e9672a8e4387a8018b59ef315e68579d",
    "Png16": "f164bd917d0df02851e956a890852caea88d418aacc3bdeb2abaa9e3b913943a",
    "SPIRV": "07b2c0d953d757adf034b87ee3ba906908f0caa80ea50f257b9a26c3455dd1e5",
    "SPIRV-Tools-shared": "2583fb5e3051644b31d4ad1f7f39338b2369fef4d3e4a1a3f4340868a8733dba",
    "SPVRemapper": "74ced91821f9794dd83f522bbe8551a5e1c806fbd4d039ab27c6fefd99e3fea3",
    "Shaderc_shared": "3537a87b7c478afa89d08f9d12827c76406add6ed59afac2406c156a615e5c4a",
    "Swresample": "cf680a10d0ca15f05236be4011454feeeaf310acec53d5f2b0edd7d6437693c8",
    "Swscale": "8f8b2a0cbbf5fdf9da2bdcb4a345d08df3d71516150c37de129d267392cc9869",
    "Uchardet": "51a52460a7d7a93d61b58b77638540b0106eb3a55a310363bc0041ab846f9214",
    "Vulkan": "5801088c3f7ff9aec14e0520d5e5e1ac97354683505bd55f7f6a039d3b846f10",
    "Xml2": "defc3cb8f47519e248547478c2f87e356162b24077ccedc69afbf051601beac7"
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
