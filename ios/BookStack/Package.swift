// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BookStack",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "BookStackShared", targets: ["BookStackShared"])
    ],
    targets: [
        .target(
            name: "BookStackShared",
            path: "Shared"
        )
    ]
)
