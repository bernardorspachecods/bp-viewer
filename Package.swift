// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "bp-viewer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "BPViewer", targets: ["BPViewerApp"]),
        .library(name: "BPViewerCore", targets: ["BPViewerCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        .target(
            name: "BPViewerCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .executableTarget(
            name: "BPViewerApp",
            dependencies: ["BPViewerCore"]
        ),
        .testTarget(
            name: "BPViewerAppTests",
            dependencies: ["BPViewerCore"]
        ),
        .executableTarget(
            name: "BPViewerContractRunner",
            dependencies: ["BPViewerCore"]
        )
    ]
)
