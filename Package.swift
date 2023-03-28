// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AsyncBoundary",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "AsyncBoundary",
            targets: ["AsyncBoundary"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/valentinradu/swift-any-error.git", from: .init(0, 0, 1))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "AsyncBoundary",
            dependencies: [
                .product(name: "AnyError", package: "swift-any-error")
            ]
        ),
        .testTarget(
            name: "AsyncBoundaryTests",
            dependencies: ["AsyncBoundary"]
        ),
    ]
)
