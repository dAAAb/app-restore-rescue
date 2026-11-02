// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppRestoreRescue",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AppRestoreRescue", targets: ["AppRestoreRescue"]),
        .library(name: "RescueCore", targets: ["RescueCore"])
    ],
    targets: [
        .target(name: "RescueCore"),
        .executableTarget(name: "AppRestoreRescue", dependencies: ["RescueCore"]),
        .testTarget(name: "RescueCoreTests", dependencies: ["RescueCore"])
    ]
)
