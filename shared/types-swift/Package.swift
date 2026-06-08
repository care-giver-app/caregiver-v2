// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CaregiverAPI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CaregiverAPI", targets: ["CaregiverAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.2"),
    ],
    targets: [
        .target(
            name: "CaregiverAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            resources: [
                .copy("openapi.yaml"),
                .copy("openapi-generator-config.yaml"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .testTarget(
            name: "CaregiverAPITests",
            dependencies: ["CaregiverAPI"]
        ),
    ]
)
