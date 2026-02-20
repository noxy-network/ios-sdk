// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoxySDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "NoxySDK", targets: ["NoxySDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.20.0"),
        .package(url: "https://github.com/sublabdev/keccak-swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "CPQClean",
            path: "Sources/CPQClean",
            exclude: ["include"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .unsafeFlags(["-Wno-unused-parameter", "-DPQCLEAN_FIPS202_PREFIX=pqclean_"]),
            ]
        ),
        .target(
            name: "NoxySDK",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                "CPQClean",
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "KeccakSwift", package: "keccak-swift"),
            ],
            path: "Sources/NoxySDK",
        ),
        .testTarget(
            name: "NoxySDKTests",
            dependencies: ["NoxySDK"],
            path: "Tests/NoxySDKTests"
        ),
    ]
)
