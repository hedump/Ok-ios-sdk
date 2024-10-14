// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Ok-ios-sdk",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "Ok-ios-sdk",
            targets: ["Ok-ios-sdk"]),
    ],
    targets: [
        .target(
            name: "Ok-ios-sdk",
            path: "Sources/Ok-ios-sdk",
            publicHeadersPath: "."
        )
    ]
)
