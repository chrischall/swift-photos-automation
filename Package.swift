// swift-tools-version: 6.4
import PackageDescription

/// Upcoming language features Swift 6 mode leaves off, plus strict memory
/// safety, applied to every target so library and tests build the same way.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .strictMemorySafety(),
]

let package = Package(
    name: "swift-photos-automation",
    platforms: [.macOS("27.2")],
    products: [
        .library(name: "PhotosAutomation", targets: ["PhotosAutomation"]),
    ],
    targets: [
        .target(
            name: "PhotosAutomation",
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "PhotosAutomationTests",
            dependencies: ["PhotosAutomation"],
            swiftSettings: swiftSettings,
        ),
    ],
    swiftLanguageModes: [.v6],
)
