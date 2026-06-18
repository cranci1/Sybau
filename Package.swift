// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sybau",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Sybau",
            targets: ["Sybau"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/mpvkit/MPVKit.git",
            from: "0.41.0"
        ),
    ],
    targets: [
        .target(
            name: "Sybau",
            dependencies: [
                .product(name: "MPVKit-GPL", package: "MPVKit"),
            ],
            path: "Player"
        ),
    ]
)
