// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PayUWebViewIOS",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "PayUWebViewIOS",
            targets: ["PayUWebViewIOS"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PayUWebViewIOS",
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
