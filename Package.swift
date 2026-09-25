// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XeneonControl",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "XeneonKit", targets: ["XeneonKit"]),
        .executable(name: "XeneonControl", targets: ["XeneonControl"]),
        .executable(name: "xeneonctl", targets: ["xeneonctl"]),
    ],
    targets: [
        .target(
            name: "XeneonKit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]
        ),
        .executableTarget(name: "XeneonControl", dependencies: ["XeneonKit"]),
        .executableTarget(name: "xeneonctl", dependencies: ["XeneonKit"]),
        .testTarget(name: "XeneonKitTests", dependencies: ["XeneonKit"]),
    ]
)
