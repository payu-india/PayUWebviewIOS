// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PayUWebview",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "PayUWebview",
            targets: ["PayUWebview"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PayUWebview",
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
