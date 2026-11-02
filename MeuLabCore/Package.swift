// swift-tools-version: 6.0
import PackageDescription

// Models shared by MeuLab iOS (MeuLabApp) and MeuLab Vision (visionOS).
let package = Package(
    name: "MeuLabCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "MeuLabCore", targets: ["MeuLabCore"]),
    ],
    targets: [
        .target(name: "MeuLabCore"),
        .testTarget(name: "MeuLabCoreTests", dependencies: ["MeuLabCore"]),
    ]
)
