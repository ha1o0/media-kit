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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-ios-build/releases/download/v1.0.0-ios.zcopy.1/libmpv-xcframeworks_v1.0.0-ios.zcopy.1_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "a68b0c245b4856df6a9c735c9b0678fd921d78453d9ae08ead58095821dbc654",
    "Avcodec": "bc55672030683e52bf0de1d5dd8c1e2bc4d9ed17b40eaf30a16c8dd611381e74",
    "Avfilter": "bba20703d9b254f88c12271a69db8d29a5aa540e3fb6d2f0f495a8646bd1b18c",
    "Avformat": "31be9d4eb41ee1901e0745e231727e05112dc315e69dc3aec299dbe3c27adf59",
    "Avutil": "928742f94b524b40c89ce8ad27d87e3352a2ec4ba840c156d6129fafc7d94742",
    "Dav1d": "56591f8b3fe923175a88f7c1960edeee35eb223e6d3c0ef902819f0ebea558ac",
    "Freetype": "120fa08fdfd9db0f72f122e6f68831afc23e77dd9ab09804f9b026dec7f2b60d",
    "Fribidi": "916b31903983a1f12a092d0327e031071b942c50f29ef2aadbd0ad032fb7c070",
    "Harfbuzz": "1c731700726e0b2954c2a54fd9796bed981199bec24fbed85baabd3122de18e3",
    "Mbedcrypto": "af4cfff39825bed47b0ce9b74532eb045737e19273b5da73d3b8cb5105d5e139",
    "Mbedtls": "135224c43a3d4b7d79b6947f6cd668bfc9c643c134819b947a8b79ab89856070",
    "Mbedx509": "4c42efd88014fba2a2f399b05e57b31fa519c6449031c6131ca05a04d5a7f56e",
    "Mpv": "d1e71fc96466eb08af1817009971bc8d7cc440a07f0102e890afe1e1c69df171",
    "Png16": "30a5d57e3afe6bf14484790c7801dcfe8bf5af7e7ba3ee5c8254e40c30b2d95c",
    "Swresample": "1f15ccbc5671d703a761de7c5bc9526679d0f164c3301464fa8df6cfd170c144",
    "Swscale": "3d1a6b5b4253bd8fe70dc1ff224557da4b0ed31dcedd29bc152c38410386df46",
    "Uchardet": "ff083e5b21df9710747243abf54ada86834a42e47f65115877e2248cf2969132",
    "Xml2": "863ab661d783216e0bbaed49a8ece07c8e467d596672d08e3f8cb49e2e0a95e9"
]
let libmpvProductTargets: [String] = ["media_kit_libs_ios_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_ios_video",
    platforms: [
        .iOS("13.0")
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
