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

let libmpvArtifactBase = "https://github.com/ha1o0/libmpv-darwin-build/releases/download/v2.20.2/libmpv-xcframeworks_v2.20.2_macos-universal-video-full"
let libmpvChecksums = [
    "Ass": "f07f1b98893c238a392b11891a0b928f2fd06d7a08ce33cecaff271ba2c20265",
    "Avcodec": "b6e56f625da75849ef35d4a016ab151e194627dd4004f67956ac84f01893ef45",
    "Avfilter": "949730bedd472991cd5f5f9a4350c804df7f9ff6039923f05210f5a7f39309f4",
    "Avformat": "f90f45f40204bd158a076251dcbe57deedd0a0fc6bdc7bfd35dadf7fc5e91dd2",
    "Avutil": "514260ce463b03282825779da81a27e444241fecabe9f2b859b54bc057bceadf",
    "Dav1d": "a4c3671993d2d6ef1f40c9ae039138efef78e61a8a9fc3129be3cea0bd1e29e3",
    "Freetype": "b70563aa42149d98b87f38d46ec22f6614e86da2aceac8f95e15c48cdbeb4018",
    "Fribidi": "638eafed68c0b7e67c622e531d11247a4c4fec2b5a24d079b597046119ebe2b2",
    "Harfbuzz": "03202ee1a8710cce3be4abd3451e38777555d8b08a1ddeb83ce03293f84b6a98",
    "Mbedcrypto": "3940b5a47436175db8b0cebc1a211a31fda8d27cc44f77ad66b23977558a5fbc",
    "Mbedtls": "579c832edad2fa6a874d705c1549daa120b3ab079deb8c4e1466039c11783eeb",
    "Mbedx509": "ba118803eb2af0696af67268d471c11e34fe2b689063bd34cf37ada5fb2b262a",
    "Mpv": "4619a1238cbe67742c686e419c98a8506fd803669d31398385423a2d72666213",
    "Png16": "ebaee8a6c0e44453b944468eecd1feb29004ab244d127a2303ddd7a7c887e1a3",
    "Swresample": "2c9d2a2a512e0299fe483ecdb2b4626faec5f6b13e2d13567897c1cb80528cfd",
    "Swscale": "f212f6a64dd29a6391af7c2a5226b101596cfa435a96e09bd6289afc87272a96",
    "Uchardet": "88958642e56d875ff5a63601a6e3f3b7da87f969fa238cb60d3b530560c623b0",
    "Xml2": "eb9afa0b324bc5e4c0ccbe4e8d961aa6d2dc0d904113ee07af7f304803291aaa"
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
