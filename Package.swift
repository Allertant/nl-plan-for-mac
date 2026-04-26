// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NLPlan",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NLPlanKit", targets: ["NLPlanKit"])
    ],
    targets: [
        .target(
            name: "NLPlanKit",
            path: "NLPlan"
        ),
        .testTarget(
            name: "NLPlanTests",
            dependencies: ["NLPlanKit"],
            path: "NLPlanTests"
        )
    ]
)
