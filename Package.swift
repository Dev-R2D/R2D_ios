// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "R2D",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "R2DCore", targets: ["R2DCore"]),
        .library(name: "R2DUIKit", targets: ["R2DUIKit"]),
        .library(name: "R2DInfrastructure", targets: ["R2DInfrastructure"]),
        .library(name: "R2DAppSupport", targets: ["R2DAppSupport"])
    ],
    dependencies: [
        .package(url: "https://github.com/inavi-systems/inavi-maps-sdk-ios", from: "0.22.0"),
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "10.15.0")
    ],
    targets: [
        .target(name: "R2DCore"),
        .target(name: "R2DUIKit", dependencies: [
            "R2DCore",
            "R2DAppSupport",
            .product(name: "GoogleMaps", package: "ios-maps-sdk", condition: .when(platforms: [.iOS])),
            .product(name: "iNaviMaps", package: "inavi-maps-sdk-ios", condition: .when(platforms: [.iOS]))
        ]),
        .target(name: "R2DInfrastructure", dependencies: ["R2DCore"], resources: [.process("Resources")]),
        .target(name: "R2DAppSupport", dependencies: ["R2DCore", "R2DInfrastructure"]),
        .testTarget(name: "R2DCoreTests", dependencies: ["R2DCore"]),
        .testTarget(name: "R2DInfrastructureTests", dependencies: ["R2DCore", "R2DInfrastructure"]),
        .testTarget(name: "R2DAppSupportTests", dependencies: ["R2DAppSupport", "R2DInfrastructure"])
    ]
)
