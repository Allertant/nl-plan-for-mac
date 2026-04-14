// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NLPlan",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NLPlan", targets: ["NLPlan"])
    ],
    targets: [
        .executableTarget(
            name: "NLPlan",
            path: "NLPlan"
        ),
        .testTarget(
            name: "NLPlanTests",
            dependencies: ["NLPlan"],
            path: "NLPlanTests"
        )
    ]
)
