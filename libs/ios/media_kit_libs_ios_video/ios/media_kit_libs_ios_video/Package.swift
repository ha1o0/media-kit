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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.4/libmpv-xcframeworks_v2.27.0-ios.4_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "cc16ba176a2f7b5ab93e47e9911513a9409e225d5e271ddd46f8aa0453cdc931",
    "Avcodec": "b4ae7312b984d0a082182b6b8af64f8f4d23cf68f2569c6a05b2ac7cdcc8b09a",
    "Avfilter": "7c7b6a6ed425ada67284a4f5213c5394b85bfbdf52c4795b6e156dd602c607ca",
    "Avformat": "d77d5d079d59c9ba24d88b00bee27bcdcc993ed4c458996eedf949c5363e735f",
    "Avutil": "d5e57e8cc03c4c717befea180295486542176a81a6d23561d4891fcd15a718d2",
    "Dav1d": "637efe87ed891470614ecbcaa4321a0204c851119f24d61479753919b317373c",
    "Freetype": "67825520286c4166cb65b8bd46ce719e1a5f64de797e13ee29c476cf168c18d5",
    "Fribidi": "abee95b5799891ddddb62457e481e0c08462c01d04489f89cd168924ea6a4ce3",
    "Harfbuzz": "145fea2aae0a523858d47c788ce7384944c9d9677cf70eb5b473db3d84c6768d",
    "Mbedcrypto": "1bdb33b447bfc4804538b950f6a6228ec62c770b94abab247ed847749e1e3e08",
    "Mbedtls": "66b91dfb7957246cfff7a863e2cb59cf06ae33b675589aec0c6a3887a7a67a89",
    "Mbedx509": "eb30280534285dfcedeed9a7498d8c897c8619e0b706602017a6b9e090dc1da8",
    "Mpv": "49da26cc04008a360888facf9aeb1cb6057010e8ad07cdcb2a049d234d0aa8ad",
    "Png16": "e65ce11746160eefa636305925456ad78f612404d76fd0f43418492a3bcbeb9d",
    "Swresample": "954d2f1ffe5765151ddd5a48177e28a51995db23920a50b0528c7b364bf71a7b",
    "Swscale": "9f69e17cdfd9a5667f709aa1b50f25e2b2e6525b3566897f0114e67cdd09872c",
    "Uchardet": "ca18594f907c198db51842890f2664515be85de7a85865e1a3c70b97d684fd99",
    "Xml2": "9df147da57d8df32628121ead3c60ceebbbfdab64672609e2af9da77b70d3135"
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
