// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GBPeerJs",
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
        
    ],
    targets: [
        .target(
            name: "GBPeerJs",
            dependencies: [],
            path: "Sources/GBPeerJs/GBPeerJs"
        ),
        .testTarget(
            name: "GBPeerJsTests",
            dependencies: ["GBPeerJs"],
            path: "Sources/GBPeerJs/GBPeerJsTests"
        )
    ]
)
