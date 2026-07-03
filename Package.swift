// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-photos-automation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PhotosAutomation", targets: ["PhotosAutomation"]),
    ],
    targets: [
        .target(name: "PhotosAutomation"),
        .testTarget(
            name: "PhotosAutomationTests",
            dependencies: ["PhotosAutomation"]
        ),
    ]
)
