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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.24.5/libmpv-xcframeworks_v2.24.5_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "76e07569097eb66dae76773172f1cf6693213a517b7d1161042606f89b9aaff3",
    "Avcodec": "4f5fd76d457f655336a6999befc438f88aab916d2921326055f8d0b2542cc2b4",
    "Avfilter": "80e1f2164db70e37c355d9331f2de7cb75f6216c742da07549cbfdb94c963966",
    "Avformat": "22d3a4610a6c268182c096097a13a9f191c8aa9764c16564608027ae373e0a98",
    "Avutil": "922759f924c28a524e1b91eeabce65125d2dcc795c720246b4137e8a11d17843",
    "Dav1d": "772404607be7fee24dde3bb192a0be62dd0c424cfbe672bb9a75dd1bb4b2718f",
    "Freetype": "873ada93598230bb0c3f8f9afe2c71a70542eb65ea605ee989dd8cbd37922635",
    "Fribidi": "501c3c19617292e55571b3a7f9b7c16a6ea6db02e0829ecfb8a312fad3c70273",
    "Harfbuzz": "790d5bd3385308980a9e927decacb4a649cf2250a463b84c985de931c6e26e1a",
    "Mbedcrypto": "c707fe57b03868cdb98ab75dc7f1c4dd34e947f386736aa0c9f488730a4e1c04",
    "Mbedtls": "c07f8a15c2b76330d72a4a252c353694962fcd642d30dff5c0d7609524cd3d27",
    "Mbedx509": "641e9d78ec90895248a75455973c139a5991fd03cdb88949704c4379020bd758",
    "Mpv": "1faebb139e8e273207f67bcaac9b041c0934a596348f92d9a16b1b5bb8eee5f7",
    "Png16": "1889dc6ecda767aa7432c34182d77b48048b086d1e37900cad492e9c082f55b3",
    "Swresample": "7db50932b2f9100af38d1caf1c819d06141e3ef9770207997a1454c529dee263",
    "Swscale": "f0fd89aa21e4337e022e27d296ce2aed6d4f54432a48e1ad2af2097d0ddf9ced",
    "Uchardet": "4aa6b3917586c701409b8656d8fe8cf454f987159e7ff27058e10a8ce263a386",
    "Xml2": "36a18202e0d02d59440c61b450574e9a4cc19263a62e4b8c188d8f1d04280b1b"
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
