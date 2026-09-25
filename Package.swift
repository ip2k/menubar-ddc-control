// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenubarDDCControl",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DDCKit", targets: ["DDCKit"]),
        .executable(name: "MenubarDDCControl", targets: ["MenubarDDCControl"]),
        .executable(name: "ddc-control", targets: ["ddc-control"]),
    ],
    targets: [
        .target(
            name: "DDCKit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]
        ),
        .executableTarget(name: "MenubarDDCControl", dependencies: ["DDCKit"]),
        .executableTarget(name: "ddc-control", dependencies: ["DDCKit"]),
        .testTarget(name: "DDCKitTests", dependencies: ["DDCKit"]),
    ]
)
