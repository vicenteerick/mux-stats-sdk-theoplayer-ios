// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mux-Stats-THEOplayer",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13)
    ],
    products: [
        .library(
            name: "MuxStatsTHEOplayer",
            targets: ["MuxStatsTHEOplayer"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/muxinc/stats-sdk-objc.git",
            exact: "4.7.1"
        ),
        .package(url: "https://github.com/vicenteerick/theoplayer-sdk-apple",
                 branch: "fix/update-swift-compatibility")
    ],
    targets: [
        .target(
            name: "MuxStatsTHEOplayer",
            dependencies: [
                .product(
                    name: "MuxCore",
                    package: "stats-sdk-objc"
                ),
                .product(
                    name: "THEOplayerSDK",
                    package: "theoplayer-sdk-apple"
                ),
            ]
        ),
        .testTarget(
            name: "MuxStatsTHEOplayerTests",
            dependencies: [
                "MuxStatsTHEOplayer",
                .product(
                    name: "MuxCore",
                    package: "stats-sdk-objc"
                ),
                .product(
                    name: "THEOplayerSDK",
                    package: "theoplayer-sdk-apple"
                ),
            ]
        ),
    ]
)
