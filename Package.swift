// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PayUIndiaWebview",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "PayUIndiaWebview",
            targets: ["PayUIndiaWebview"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PayUIndiaWebview",
            dependencies: [],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("WebKit")
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
