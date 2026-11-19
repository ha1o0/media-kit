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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.2/libmpv-xcframeworks_v2.27.0-ios.2_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "b3aba3cc39d4c7002fde1fb170bfb5a5fc7ea9944e2199cadae15a0c1fa88792",
    "Avcodec": "2611acb6db986a0e6b220d11f6569393a2d89bad95afc8040c1c9a95d8caa6b6",
    "Avfilter": "41c3eff2256c7471f3f1474e4e28a1c6352ca0b92be924a38358607f64844c1c",
    "Avformat": "261963da0ca0059fd1666965c57da1664facebae2593ca5c7c5d8091d6ccd9fe",
    "Avutil": "85a9867852c67671d6cf414ee250dacaf2f1d353179dd59235ef1db1e136e304",
    "Dav1d": "b59625efcb01c35053c831e5e3e4a2207616306baf2cd48efb08c48505cf988e",
    "Freetype": "bbf4c65d1589ec66d36ddda4c9b5beccf32ead543630ff8366718d13f5cdd803",
    "Fribidi": "f0aab4afb05dfd91ee2e6289e66aef9227279f916f854bcf3050e0e3ee3511f7",
    "Harfbuzz": "9af6e6a984a228691941b63e70ce6a293034e055e85c048339bdbefd87d2ffa9",
    "Mbedcrypto": "0f23757791f5f0fe8b9c3f5107e3ae3c4fc443000f93ecb5c98a8a00256abc07",
    "Mbedtls": "378913c497bc6cef153d5f0b88d23b52a7d1271fa2423ef626919163a325afcf",
    "Mbedx509": "3e6f930c81f713cbf0f8c2fef7d42fd294085e4456e849f12ac25a6e69b34dc4",
    "Mpv": "6409d6e29829bc1042da7fc3c905a9854cbeb4f6c1d26c8b0b2f7d446ab37e71",
    "Png16": "ae09d0b94029db9e371a4e352b129036bd30152c621edf7599304ce8248f516c",
    "Swresample": "aed3b1ebfa2970667b3db687882b40f36a535e2f88f1907ba78b6b0bd5f71c8b",
    "Swscale": "2cbb6bd2b817402b4d05f46037f66b2c0aac0ce1abf111e2bad259fc89e3095e",
    "Uchardet": "01c37f638a2bb15d718ae5f12604c164eec53e86ad7c71c82657aae8069956ce",
    "Xml2": "d4b30354508078e824de58ead38ea5dc13dc19093e927c5e5f59c1448c0eb4f7"
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
