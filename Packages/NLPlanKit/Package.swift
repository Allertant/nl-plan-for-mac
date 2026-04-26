// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NLPlanKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NLPlanKit", targets: ["NLPlanKit"])
    ],
    targets: [
        .target(name: "NLPlanKit"),
        .testTarget(
            name: "NLPlanKitTests",
            dependencies: ["NLPlanKit"],
            path: "Tests/NLPlanKitTests"
        )
    ]
)
