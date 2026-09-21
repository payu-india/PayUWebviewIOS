// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PayUWebView",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "PayUWebView",
            targets: ["PayUWebView"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PayUWebView",
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
