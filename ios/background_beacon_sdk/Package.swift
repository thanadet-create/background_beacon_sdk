// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "background_beacon_sdk",
    platforms: [
        // iOS 13 ขั้นต่ำ — ต้องตรงกับ s.platform ใน podspec (สอง manifest คู่กัน
        // จนกว่า CocoaPods จะถูกถอด)
        .iOS("13.0")
    ],
    products: [
        // ชื่อ product ต้องเป็น dash: tool ฝั่ง app generate dependency เป็น
        // ชื่อ plugin ที่แทน _ ด้วย - (library name ห้ามมี underscore
        // เพราะถูกใช้เป็น CFBundleIdentifier ตอน link แบบ dynamic)
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
                // Privacy manifest ยังว่าง — SDK ไม่ใช้ required-reason APIs
                // (CoreLocation ไม่อยู่ในลิสต์) การเก็บ location data เป็น
                // ความรับผิดชอบฝั่ง app ที่ integrate ต้องประกาศเอง
                // .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
