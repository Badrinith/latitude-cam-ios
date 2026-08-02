// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LatitudeCam",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "LatitudeCam", targets: ["LatitudeCam"]),
    ],
    targets: [
        .target(
            name: "LatitudeCam",
            path: "LatitudeCam/Sources",
            publicHeadersPath: "."
        ),
        .testTarget(
            name: "LatitudeCamTests",
            dependencies: ["LatitudeCam"],
            path: "Tests/Unit"
        ),
    ]
)
