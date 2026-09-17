// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlanAI",
    defaultLocalization: "es",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "PlanAICore",
            targets: ["PlanAICore"]
        )
    ],
    targets: [
        .target(
            name: "PlanAICore",
            path: "PlanAI",
            exclude: ["Info.plist", "App/PlanAIApp.swift"],
            resources: [
                .process("Localization/Resources")
            ]
        ),
        .testTarget(
            name: "PlanAITests",
            dependencies: ["PlanAICore"],
            path: "Tests/PlanAITests"
        )
    ]
)
