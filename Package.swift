// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "R2D",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "R2DCore", targets: ["R2DCore"]),
        .library(name: "R2DUI", targets: ["R2DUI"]),
        .library(name: "R2DInfrastructure", targets: ["R2DInfrastructure"]),
        .library(name: "R2DAppSupport", targets: ["R2DAppSupport"])
    ],
    targets: [
        .target(name: "R2DCore"),
        .target(name: "R2DUI", dependencies: ["R2DCore"]),
        .target(name: "R2DInfrastructure", dependencies: ["R2DCore"], resources: [.process("Resources")]),
        .target(name: "R2DAppSupport", dependencies: ["R2DCore", "R2DUI", "R2DInfrastructure"]),
        .testTarget(name: "R2DCoreTests", dependencies: ["R2DCore"]),
        .testTarget(name: "R2DInfrastructureTests", dependencies: ["R2DCore", "R2DInfrastructure"]),
        .testTarget(name: "R2DAppSupportTests", dependencies: ["R2DAppSupport", "R2DInfrastructure"])
    ]
)
