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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.9/libmpv-xcframeworks_v2.27.0-ios.9_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "27a17a3a6428212be649887085cf11f0678d1624cb8a816172cc81212a258a74",
    "Avcodec": "2e21d658cb00cd64217dafcbf47e0783d50830004b847a77b8190bbb33da3437",
    "Avfilter": "669c437589196f99ebab49ba97d9eadab3e60d927b5d8cc85dc83e71658c38bd",
    "Avformat": "b86151147c55ee4afa9879b82dbe695e2b6acf758039612f41c8b75283512a88",
    "Avutil": "bcb0250551c4798080f93a82938c9904802d833b9ff5e74d35550017f0b82df8",
    "Dav1d": "7e32dc4f1ac282e632e3dde763ddc222071eac8c9285c9458991bc5a5867a15a",
    "Freetype": "1a1fc99f7e71de91b2ccab7c404e67bcfd16e4ecd30892c5aad599d053ad487c",
    "Fribidi": "4d3a0acca97ff774080be8e52becd02171ce1f30239132ad6eb1fe37211c8a2a",
    "Harfbuzz": "d7bd48700165e6e0a539952b209012b4386b6ddd616dccc2d3807c28ecff7acf",
    "Mbedcrypto": "6c341b6265b9fcb0b54c648470474e3ca791e6b242d5dd5b22dcac7b455bc0c0",
    "Mbedtls": "31e7b955fd0200eba356f040b654c984bd4f538d30cd95eb97d8c1ce1e2d823a",
    "Mbedx509": "3df6486b40cdbb9d99583473fd137365cb00f2dbb1c853cf11b073a9fd3f1809",
    "Mpv": "6f99361442617501ed9809afe7bb9db8e8096ead9a4e923a4e8f16e83c4d51c8",
    "Png16": "ebbc3ee3f85e7acfa5a0c72acfbe8cf3371a7f8da6f275bf8d340c499d91aadb",
    "Swresample": "14f7f54601e5c4aa496fee1c9624b5fd722f4412a5432a92d8659157ae390193",
    "Swscale": "371ec7d00a945c48d05ac2a49423424d3199166b4f95d2797ed3159bfb881055",
    "Uchardet": "ed70cec51e6538c16731f0ec34de42e2abc985a870d13df23cec3e899d232464",
    "Xml2": "1368420e3144d11af3af0e9eced578df70ad5df44d8d88e67df085357fdcb00d"
]
let libmpvProductTargets: [String] = ["media_kit_libs_ios_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_ios_video",
    platforms: [
        .iOS("15.0")
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
