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
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "BPViewerCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            exclude: ["CONTEXT.md"]
        ),
        .executableTarget(
            name: "BPViewerApp",
            dependencies: ["BPViewerCore"],
            exclude: ["CONTEXT.md"]
        ),
        .testTarget(
            name: "BPViewerAppTests",
            dependencies: [
                "BPViewerCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
        .executableTarget(
            name: "BPViewerContractRunner",
            dependencies: ["BPViewerCore"]
        ),
        .executableTarget(
            name: "BPViewerFoundationRunner",
            dependencies: ["BPViewerCore"]
        ),
        .executableTarget(
            name: "BPViewerTabPrototype",
            dependencies: []
        ),
        .executableTarget(
            name: "BPViewerWindowTabPrototype",
            dependencies: []
        )
    ]
)
