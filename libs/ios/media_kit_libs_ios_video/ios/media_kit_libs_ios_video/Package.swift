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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.19.5/libmpv-xcframeworks_v2.19.5_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "3e17ded6b31bb44a492ceeee7735e9a7fd57d4d1b5cab7fa57524cdd49884554",
    "Avcodec": "6aa9a353d4942c82bd5cd5d09051f4da8b3ad22d35aaa9dc2fc07e046d00c5f9",
    "Avfilter": "b1262a0f75357d2ac9fef0afa9d56380f25ad24650e403873c9d75410a814cb7",
    "Avformat": "281e0ca8f2fb12e0b38bc2efc30dfe1cc0711412868bdcf1943678a1e9eccf59",
    "Avutil": "cae0d9a5d421c9b700713d6890fb937c4a384c3e42750d10bbadbf5508e7a42e",
    "Dav1d": "dca450247b050d22a1067940d7ac8d4a2528a7461cee6cbcac6183fff1c9eb9c",
    "Freetype": "083de20629ca95a9eaeed35f9e1f96b3fb07f85ce8bd720932b8c30e88969748",
    "Fribidi": "a6cef11d5e34f5f6eb44282f53714cec04473fd528ec8a2bf93b90aaa83f07d6",
    "Harfbuzz": "142536dc0f2bcafd437630fe604270bcbbd8d2a982126a0c0fc9a01dba913caa",
    "Mbedcrypto": "1d91036b8e5e36e3a24df4122f5fd9299ec415ab85a74d8afaa367b70d70769b",
    "Mbedtls": "11756a020ecccdd547cef07be1757cb0020350ec2b48d5e0af2aa7892aaddeed",
    "Mbedx509": "ef3fd625a45eaf045a03db8d07be97868e7d5e4791cefd4b6a69a0805b8780fc",
    "Mpv": "792534b7cbbe14bba547065a949c7fef32cdb22f63de9b1b3d561d192a3c32c7",
    "Png16": "fef6124049ba9c63a2fd010d66536c1928906ad87830cbbb2d9e301e64e78a43",
    "Swresample": "a83db6b1cdb2d2b22166bda45db343a95f567627a272500681c3636b5f18a337",
    "Swscale": "c7cf0bb94f1ef796f5129d65e93177d86e062029e75975b8bd118a94831376fd",
    "Uchardet": "4f490b35646014a3e55125f117951f0a2161bcc10f3da7b99ab9195e2c58b1af",
    "Xml2": "34d42ef94071e6f35a972bc9f20e4cfee8ad481a84c425a2a4c501ffee4d18ed"
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
