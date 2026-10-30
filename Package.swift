// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "swift-photos-automation",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PhotosAutomation", targets: ["PhotosAutomation"]),
    ],
    targets: [
        .target(
            name: "PhotosAutomation",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .testTarget(
            name: "PhotosAutomationTests",
            dependencies: ["PhotosAutomation"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
