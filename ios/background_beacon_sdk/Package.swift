// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "background_beacon_sdk",
    platforms: [
        // iOS 13 minimum — must match s.platform in the podspec (the two
        // manifests live side by side until CocoaPods is dropped)
        .iOS("13.0")
    ],
    products: [
        // Product name must use dashes: the app-side tool generates the
        // dependency as the plugin name with _ replaced by - (library names
        // can't contain underscores — they become the CFBundleIdentifier
        // when linked dynamically)
        .library(name: "background-beacon-sdk", targets: ["background_beacon_sdk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "background_beacon_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // Privacy manifest still empty — the SDK uses no
                // required-reason APIs (CoreLocation isn't on the list);
                // declaring location data collection is the integrating
                // app's responsibility
                // .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
