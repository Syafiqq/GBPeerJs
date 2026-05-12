// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GBPeerJs",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "GBPeerJs",
            targets: ["GBPeerJs"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.8"),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "6.0.0")),
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "125.6422.32"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "GBPeerJs",
            dependencies: [
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxCocoa", package: "RxSwift"),
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework")
            ],
            path: "Library/GBPeerJs/Sources/GBPeerJs",
            plugins: [
            ]
        ),
        .testTarget(
            name: "GBPeerJsTests",
            dependencies: [
                "GBPeerJs",
            ],
            path: "Library/GBPeerJs/Tests/GBPeerJsTests",
            plugins: [
            ]
        )
    ]
)
