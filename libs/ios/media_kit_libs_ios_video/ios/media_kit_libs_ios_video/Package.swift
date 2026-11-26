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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.27.0-ios.15/libmpv-xcframeworks_v2.27.0-ios.15_ios-universal-video-full"
let libmpvChecksums = [
    "Ass": "93ef1b0a4edb2e5913116f948a37e8389be72927bf563fdb5a87fb0926fb4c14",
    "Avcodec": "4aec09c7f21273cf2f0e7af9a1464e8ac53a10e76ec45d5b3f0c2587456a5c95",
    "Avfilter": "f4958e1a918e4734dfdf4284409e4942a942456c7838e6e6fc7298b34ad456e9",
    "Avformat": "dee05babd6bcf74ac074b7e6e6f97055a024597178b75684a9cb7b5ed24e7793",
    "Avutil": "e3ece75c521127e7fe1d026468f468c228238b48dfbd59ff4dccc30cd58ff9ae",
    "Dav1d": "b3c5045bc5f08f70b08b5dbe9ee5d885e796301325c135ee10b72e9ce0d8e21c",
    "Freetype": "573da8ac80318e323a0053b88ec0c98504b67bada442c32fe951082571bd3eb8",
    "Fribidi": "cc8f93937e81bb69a146d9de7af33907596cc308fb795a50024aab39a3dac77c",
    "Harfbuzz": "13adeedefa070f18daaf301121a15f4b90e33976e29a8537c4a1e564e3b9a777",
    "Mbedcrypto": "62f1fae69944095b00ba2ad2b4b18f24f7f7acd155b5ffa9bebc95dcf2bc02d9",
    "Mbedtls": "acff2bbe05efadbf7ee32450a79fae69654b782e1667dbba8480deb827219127",
    "Mbedx509": "a52d3f66da6eac64940df1b84c5d56e0525974d313527750fd5ae2473d995496",
    "Mpv": "4993e9c45e8ede63161f0bf3117f3715b769ef3e60af17c96f2e87c7377ac4f0",
    "Png16": "89c9eb8d0dcd721db54a0b4e9bfa639cca2c17770abaa05e35cca9a46a89d8f7",
    "Swresample": "eaf2d4ec26890a373df11c195f237ea2182b8d7299ee0fcad12b80ef90380aad",
    "Swscale": "b5a2c973bccacde23394a113d07c941e79c2ffc8b53326ea4398f7a753db1659",
    "Uchardet": "fac4dd3374b2c2af45147a4d84a014d4e3c439ec578414609b269845ceceffec",
    "Xml2": "96050116cb2e0ed296106d7f410362d1a2c33e3863e47420f24d76cb556081fe"
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
