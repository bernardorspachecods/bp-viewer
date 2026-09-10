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
    targets: [
        .executableTarget(
            name: "BPViewerApp"
        )
    ]
)
