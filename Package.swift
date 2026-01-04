// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GBPeerJs",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "GBPeerJs",
            targets: ["GBPeerJs"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.8"),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", from: "6.9.1"),
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "125.6422.32"),
    ],
    targets: [
        .target(
            name: "GBPeerJs",
            dependencies: [
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxCocoa", package: "RxSwift"),
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework")
            ],
            path: "Sources/GBPeerJs/GBPeerJs"
        ),
        .testTarget(
            name: "GBPeerJsTests",
            dependencies: ["GBPeerJs"],
            path: "Sources/GBPeerJs/GBPeerJsTests"
        )
    ]
)
