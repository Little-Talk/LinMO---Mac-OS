// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LinMO",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "LinMO",
            path: "Sources/LinMO",
            linkerSettings: [
                .linkedFramework("Virtualization")
            ]
        )
    ]
)
