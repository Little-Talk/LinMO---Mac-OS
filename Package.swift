// swift-tools-version:5.9
import Foundation
import PackageDescription

let useSparkle = ProcessInfo.processInfo.environment["LINMO_NO_SPARKLE"] == nil

let package = Package(
    name: "LinMO",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: useSparkle ? [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ] : [],
    targets: [
        .executableTarget(
            name: "LinMO",
            dependencies: useSparkle ? [
                .product(name: "Sparkle", package: "Sparkle")
            ] : [],
            path: "Sources/LinMO",
            linkerSettings: [
                .linkedFramework("Virtualization")
            ]
        )
    ]
)
