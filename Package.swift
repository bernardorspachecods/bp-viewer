// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "bp-viewer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "BPViewer", targets: ["BPViewerApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        .executableTarget(
            name: "BPViewerApp",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .testTarget(
            name: "BPViewerAppTests",
            dependencies: ["BPViewerApp"]
        )
    ]
)
