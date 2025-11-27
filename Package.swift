// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AIDataAssistant",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AIDataAssistantCore",
            targets: ["AIDataAssistantCore"]
        )
    ],
    dependencies: [
        // SQLite support
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        // MySQL support
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.7.0"),
        .package(url: "https://github.com/vapor/mysql-kit.git", from: "4.8.0"),
    ],
    targets: [
        // Core library
        .target(
            name: "AIDataAssistantCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
            ],
            path: "Sources/Core"
        ),
    ]
)

