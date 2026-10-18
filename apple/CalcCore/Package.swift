// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalcCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "CalcCore", targets: ["CalcCore"])],
    targets: [
        .target(name: "CalcCore"),
        .testTarget(name: "CalcCoreTests", dependencies: ["CalcCore"]),
    ]
)
